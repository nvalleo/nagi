// MozcClient+MachIPC — the actual IPC framing.
//
// On macOS, Mozc does NOT talk over a Unix domain socket. Tracing
// google/mozc's src/ipc/BUILD.bazel: `ipc.cc`, `mach_ipc.cc` and
// `unix_ipc.cc` are all compiled into the same `ipc` library, but
// unix_ipc.cc is guarded by `#if defined(__linux__)` — the mac build
// (`#ifdef __APPLE__` in mach_ipc.cc) always wins. mozc_server registers a
// Mach bootstrap service via launchd (see
// data/mac/com.google.inputmethod.Japanese.Converter.plist upstream, or
// `launchctl list | grep inputmethod` for the installed build), and the
// client looks it up with `bootstrap_look_up` before exchanging raw
// protobuf bytes over `mach_msg` using an out-of-line (OOL) descriptor.
//
// This file mirrors `IPCClient::Call()` in src/ipc/mach_ipc.cc as closely
// as reasonable in Swift. See poc/README.md, "Surprises", for the write-up
// aimed at whoever picks up M1/M2.
//
// IMPORTANT — why the mach_msg calls below go through
// `withUnsafeMutableBytes(of:)` on the *whole* message struct instead of
// `withUnsafeMutablePointer(to: &msg.header)`: mach_msg() is a C function
// that, from Swift's point of view, only takes a pointer to the `header`
// field. Swift's law-of-exclusivity/optimizer takes that at face value and
// assumes the call cannot have touched `.body` / `.data` / `.count` /
// `.trailer` — which is wrong, since the *kernel* writes the received
// descriptor straight into that memory via the header pointer, entirely
// outside Swift's aliasing model. The result was not a crash but something
// much nastier: `mach_msg` genuinely received the full reply (confirmed by
// dumping the raw bytes of the struct — real address/size were there), yet
// reading `receiveMessage.data.address` / `.size` afterward silently
// returned nil/0, because the compiler treated those fields as unchanged.
// Taking mutable bytes over the entire struct (not just `.header`) tells
// Swift the whole region may have changed, so it re-reads from memory
// instead of trusting stale values. Worth its own paragraph in
// poc/README.md for whoever hits this next.
//
// Verify note: `mach_msg_ool_descriptor_t`'s LP64 layout also isn't what a
// first read of mach_ipc.cc suggests — on 64-bit it's
// `address, {deallocate,copy,pad1,type} bitfield, size` (size comes *after*
// the bitfields, not right after `address` — see `<mach/message.h>`, the
// `#if defined(__LP64__)` branch). Doesn't matter if you always go through
// the named Swift properties (the importer gets the offsets right), but it
// will bite you if you ever try to hand-compute byte offsets for debugging.

import CMozcMach
import Darwin
import Foundation

extension MozcClient {

    /// Mirrors mozc's `IPC_PROTOCOL_VERSION` (src/ipc/ipc.h). Sent as
    /// `msgh_id` on the way out; the server echoes it back so we can tell
    /// a real reply from noise on the receive port.
    static let ipcProtocolVersion: mach_msg_id_t = 3

    /// Looks up the Mach bootstrap service for mozc_server's session port.
    /// Note: like mozc's own `DefaultClientMachPortManager`, this call
    /// transparently starts the server via launchd if it isn't running yet
    /// — there's no separate "launch the server" step to do ourselves.
    static func lookUpConverterPort(serviceName: String) throws -> mach_port_t {
        var port: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let kr = serviceName.withCString { cName in
            bootstrap_look_up(bootstrap_port, cName, &port)
        }
        guard kr == KERN_SUCCESS else {
            throw MozcError.socketNotFound(
                path: "mach service '\(serviceName)' (bootstrap_look_up kr=\(kr))"
            )
        }
        return port
    }

    /// Sends `request` (a serialized `Input`) to `serverPort` and returns
    /// the raw response bytes (a serialized `Output`). One call is one
    /// round trip: allocate a private receive port, send an OOL message
    /// naming it as the reply port, then block on that port for the
    /// server's answer.
    func machCall(_ request: Data, serverPort: mach_port_t, timeout: TimeInterval) throws -> Data {
        var clientPort: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let allocKr = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &clientPort)
        guard allocKr == KERN_SUCCESS else {
            throw MozcError.protocolError("mach_port_allocate failed: \(allocKr)")
        }
        defer { mach_port_deallocate(mach_task_self_, clientPort) }

        // The OOL payload buffer must stay alive across the mach_msg send
        // call. We keep `deallocate = false` + `copy = VIRTUAL_COPY`
        // (copy-on-write), matching mach_ipc.cc, so we own freeing it.
        let byteCount = max(request.count, 1)
        let requestBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<UInt8>.alignment
        )
        defer { requestBuffer.deallocate() }
        request.withUnsafeBytes { raw in
            if let base = raw.baseAddress, raw.count > 0 {
                requestBuffer.copyMemory(from: base, byteCount: raw.count)
            }
        }

        let timeoutMillis = mach_msg_timeout_t(max(timeout, 0) * 1000)

        var sendMessage = nagi_mach_ipc_send_message_t()
        sendMessage.header.msgh_bits =
            UInt32(MACH_MSG_TYPE_COPY_SEND) | (UInt32(MACH_MSG_TYPE_MAKE_SEND) << 8) | MACH_MSGH_BITS_COMPLEX
        sendMessage.header.msgh_size = mach_msg_size_t(MemoryLayout<nagi_mach_ipc_send_message_t>.size)
        sendMessage.header.msgh_remote_port = serverPort
        sendMessage.header.msgh_local_port = clientPort
        sendMessage.header.msgh_id = Self.ipcProtocolVersion
        sendMessage.body.msgh_descriptor_count = 1
        sendMessage.data.address = requestBuffer
        sendMessage.data.size = mach_msg_size_t(request.count)
        sendMessage.data.deallocate = 0
        sendMessage.data.copy = UInt32(MACH_MSG_VIRTUAL_COPY)
        sendMessage.data.type = UInt32(MACH_MSG_OOL_DESCRIPTOR)
        sendMessage.count = mach_msg_type_number_t(request.count)

        let sendSize = sendMessage.header.msgh_size
        let sendKr = withUnsafeMutableBytes(of: &sendMessage) { raw -> kern_return_t in
            let headerPtr = raw.baseAddress!.assumingMemoryBound(to: mach_msg_header_t.self)
            return mach_msg(
                headerPtr,
                mach_msg_option_t(MACH_SEND_MSG | MACH_SEND_TIMEOUT),
                sendSize,
                0,
                mach_port_t(MACH_PORT_NULL),
                timeoutMillis,
                mach_port_t(MACH_PORT_NULL)
            )
        }
        guard sendKr == MACH_MSG_SUCCESS else {
            if sendKr == MACH_SEND_TIMED_OUT {
                throw MozcError.protocolError("mach_msg send timed out after \(timeout) s")
            }
            throw MozcError.protocolError("mach_msg send failed: kr=\(sendKr)")
        }

        // mozc's own client tries to receive twice (a stray message from
        // another process could land first) — mirror that here.
        var lastError = MozcError.protocolError("no response received on client port")
        for _ in 0..<2 {
            var receiveMessage = nagi_mach_ipc_receive_message_t()
            receiveMessage.header.msgh_local_port = clientPort
            receiveMessage.header.msgh_size = mach_msg_size_t(MemoryLayout<nagi_mach_ipc_receive_message_t>.size)

            let receiveSize = receiveMessage.header.msgh_size
            let recvKr = withUnsafeMutableBytes(of: &receiveMessage) { raw -> kern_return_t in
                let headerPtr = raw.baseAddress!.assumingMemoryBound(to: mach_msg_header_t.self)
                return mach_msg(
                    headerPtr,
                    mach_msg_option_t(MACH_RCV_MSG | MACH_RCV_TIMEOUT),
                    0,
                    receiveSize,
                    clientPort,
                    timeoutMillis,
                    mach_port_t(MACH_PORT_NULL)
                )
            }

            if recvKr == MACH_RCV_TIMED_OUT {
                lastError = .protocolError("mach_msg receive timed out after \(timeout) s")
                break
            }
            guard recvKr == MACH_MSG_SUCCESS else {
                lastError = .protocolError("mach_msg receive failed: kr=\(recvKr)")
                continue
            }
            guard receiveMessage.header.msgh_id == Self.ipcProtocolVersion else {
                lastError = .protocolError("unexpected msgh_id \(receiveMessage.header.msgh_id) in reply")
                continue
            }
            guard let address = receiveMessage.data.address else {
                lastError = .protocolError("reply had no OOL payload")
                continue
            }

            let responseData = Data(bytes: address, count: Int(receiveMessage.data.size))
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: address)),
                vm_size_t(receiveMessage.data.size)
            )
            return responseData
        }

        throw lastError
    }
}

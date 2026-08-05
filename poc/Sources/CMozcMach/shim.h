// CMozcMach — thin system-library shim exposing the Mach bootstrap APIs
// (bootstrap_look_up et al.) that Swift's `Darwin` module does not import
// by default.
//
// Why this exists: mozc_server on macOS is *not* reachable over a Unix
// domain socket. src/ipc/{unix_ipc.cc,mach_ipc.cc} in google/mozc show
// unix_ipc.cc is compiled only under `#if defined(__linux__)`; the mac
// build always uses mach_ipc.cc, which talks to a launchd-registered Mach
// bootstrap service via bootstrap_look_up() + raw mach_msg(). See
// poc/README.md, "Surprises" section, for the write-up.
//
// The message-shape structs (nagi_mach_ipc_send_message_t /
// nagi_mach_ipc_receive_message_t below) are defined in C rather than
// composed from Swift-side struct fields so their memory layout is
// guaranteed to match what mozc_server expects — Swift does not promise
// C-compatible layout for a Swift struct that merely contains C types.
// They mirror mach_ipc_send_message / mach_ipc_receive_message in
// src/ipc/mach_ipc.cc exactly.

#ifndef NAGI_CMOZCMACH_SHIM_H
#define NAGI_CMOZCMACH_SHIM_H

#include <mach/mach.h>
#include <mach/message.h>
#include <servers/bootstrap.h>

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_ool_descriptor_t data;
    mach_msg_type_number_t count;
} nagi_mach_ipc_send_message_t;

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_ool_descriptor_t data;
    mach_msg_type_number_t count;
    mach_msg_trailer_t trailer;
} nagi_mach_ipc_receive_message_t;

#endif  // NAGI_CMOZCMACH_SHIM_H

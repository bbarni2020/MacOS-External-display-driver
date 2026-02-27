#!/usr/bin/env python3

import argparse
import logging
import socket
import struct
import time


logger = logging.getLogger(__name__)


def recv_exact(conn, size):
    chunk = bytearray()
    while len(chunk) < size:
        try:
            part = conn.recv(size - len(chunk))
        except (ConnectionResetError, BrokenPipeError, OSError):
            return None
        if not part:
            return None
        chunk.extend(part)
    return bytes(chunk)


def create_server_socket(host, port):
    infos = socket.getaddrinfo(host, port, socket.AF_UNSPEC, socket.SOCK_STREAM, 0, socket.AI_PASSIVE)

    last_error = None
    for family, socktype, proto, _, sockaddr in infos:
        try:
            server = socket.socket(family, socktype, proto)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if family == socket.AF_INET6:
                server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            server.bind(sockaddr)
            server.listen(5)
            return server, sockaddr
        except OSError as exc:
            last_error = exc
            try:
                server.close()
            except Exception:
                pass

    if last_error:
        raise last_error
    raise RuntimeError("No usable socket address found")


def run_receiver(host, port, max_frames, timeout, once):
    server, sockaddr = create_server_socket(host, port)
    with server:
        logger.info("Listening on %s", sockaddr)

        total_frames = 0
        total_bytes = 0
        global_start = time.time()
        interrupted = False

        while True:
            try:
                conn, addr = server.accept()
            except KeyboardInterrupt:
                interrupted = True
                logger.info("Interrupted by user")
                break

            with conn:
                if timeout > 0:
                    conn.settimeout(timeout)
                else:
                    conn.settimeout(None)
                logger.info("Connected by %s:%d", addr[0], addr[1])

                session_start = time.time()
                session_frames = 0
                session_bytes = 0
                last_report = session_start

                while True:
                    try:
                        header = recv_exact(conn, 4)
                    except KeyboardInterrupt:
                        interrupted = True
                        logger.info("Interrupted by user")
                        break
                    except socket.timeout:
                        logger.warning("Socket timeout while waiting for frame header")
                        break

                    if header is None:
                        logger.info("Sender disconnected")
                        break

                    frame_size = struct.unpack("!I", header)[0]

                    try:
                        payload = recv_exact(conn, frame_size)
                    except KeyboardInterrupt:
                        interrupted = True
                        logger.info("Interrupted by user")
                        break
                    except socket.timeout:
                        logger.warning("Socket timeout while reading frame payload")
                        break

                    if payload is None:
                        logger.warning("Disconnected while reading frame payload")
                        break

                    session_frames += 1
                    session_bytes += frame_size
                    total_frames += 1
                    total_bytes += frame_size

                    now = time.time()
                    if now - last_report >= 1.0:
                        session_elapsed = max(now - session_start, 1e-6)
                        session_fps = session_frames / session_elapsed
                        session_mbps = (session_bytes * 8) / session_elapsed / 1_000_000
                        logger.info(
                            "session_frames=%d last_frame=%d bytes fps=%.2f mbps=%.2f",
                            session_frames,
                            frame_size,
                            session_fps,
                            session_mbps,
                        )
                        last_report = now

                    if max_frames > 0 and total_frames >= max_frames:
                        logger.info("Reached max frames limit: %d", max_frames)
                        break

                if interrupted:
                    break

                session_elapsed = max(time.time() - session_start, 1e-6)
                logger.info(
                    "Session summary: frames=%d bytes=%d duration=%.2fs fps=%.2f mbps=%.2f",
                    session_frames,
                    session_bytes,
                    session_elapsed,
                    session_frames / session_elapsed,
                    (session_bytes * 8) / session_elapsed / 1_000_000,
                )

            if max_frames > 0 and total_frames >= max_frames:
                break

            if once:
                logger.info("--once is set; exiting after first connection")
                break

            if interrupted:
                break

            logger.info("Waiting for next connection...")

        global_elapsed = max(time.time() - global_start, 1e-6)
        logger.info(
            "Server summary: total_frames=%d total_bytes=%d duration=%.2fs fps=%.2f mbps=%.2f",
            total_frames,
            total_bytes,
            global_elapsed,
            total_frames / global_elapsed,
            (total_bytes * 8) / global_elapsed / 1_000_000,
        )


def build_parser():
    parser = argparse.ArgumentParser(
        description="Simple localhost receiver for DeskExtend macOS sender testing"
    )
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=5900, help="Bind port (default: 5900)")
    parser.add_argument("--max-frames", type=int, default=0, help="Stop after N frames (0 = unlimited)")
    parser.add_argument("--timeout", type=float, default=0.0, help="Socket timeout in seconds (0 = no timeout)")
    parser.add_argument("--once", action="store_true", help="Exit after first connection closes")
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level",
    )
    return parser


def main():
    args = build_parser().parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s - %(levelname)s - %(message)s",
    )
    run_receiver(args.host, args.port, args.max_frames, args.timeout, args.once)


if __name__ == "__main__":
    main()
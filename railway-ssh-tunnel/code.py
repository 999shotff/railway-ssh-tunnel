#!/usr/bin/env python3
"""
ws_bridge.py - HTTP/WebSocket -> raw TCP (SSHD) bridge.
- GET with Upgrade header  -> replies 101, then raw-pipes to sshd
- CONNECT method           -> replies 200 Connection established, raw-pipes to sshd
- plain GET                -> health page (Railway healthcheck friendly)
"""
import asyncio
import os

SSH_HOST = os.environ.get("SSH_HOST", "127.0.0.1")
SSH_PORT = int(os.environ.get("SSH_PORT", "22"))
LISTEN_PORT = int(os.environ.get("PORT", "8080"))
HEALTH_HTML = b"<h1>Tunnel OK</h1>"


async def pump(src, dst):
    try:
        while True:
            data = await src.read(65536)
            if not data:
                break
            dst.write(data)
            await dst.drain()
    except Exception:
        pass
    finally:
        for w in (src, dst):
            try:
                w.close()
            except Exception:
                pass


async def handle(reader, writer):
    try:
        buf = b""
        while b"\r\n\r\n" not in buf and b"\n\n" not in buf:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=15)
            if not chunk:
                return
            buf += chunk
            if len(buf) > 65536:
                return

        first_line = buf.split(b"\r\n", 1)[0].decode("latin1", "ignore")
        method = first_line.split(" ")[0].upper() if " " in first_line else ""
        head = buf[:4096].lower()

        rest = b""
        for sep in (b"\r\n\r\n", b"\n\n"):
            if sep in buf:
                rest = buf.split(sep, 1)[1]
                break

        if b"upgrade" in head:
            writer.write(b"HTTP/1.1 101 Switching Protocols\r\n"
                         b"Upgrade: websocket\r\n"
                         b"Connection: Upgrade\r\n\r\n")
            await writer.drain()
        elif method == "CONNECT":
            writer.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            await writer.drain()
        else:
            body = HEALTH_HTML
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
                         b"Connection: close\r\n"
                         b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
            await writer.drain()
            writer.close()
            return

        up_reader, up_writer = await asyncio.open_connection(SSH_HOST, SSH_PORT)
        if rest:
            up_writer.write(rest)
            await up_writer.drain()

        t1 = asyncio.create_task(pump(reader, up_writer))
        t2 = asyncio.create_task(pump(up_reader, writer))
        await asyncio.gather(t1, t2)
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", LISTEN_PORT)
    print(f"[ws_bridge] listening on :{LISTEN_PORT} -> sshd {SSH_HOST}:{SSH_PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())

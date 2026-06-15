#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime
import json


HOST = "0.0.0.0"
PORT = 8080


class CallbackHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        raw = self._read_body()

        try:
            event = self._parse_event(raw)
            self._print_event(event)
        except Exception as e:
            self._print_error(e)

        self._reply_ok()

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length)

    def _parse_event(self, raw):
        data = json.loads(raw.decode("utf-8", errors="ignore"))

        extra_raw = data.get("extra", "[]")
        extra = json.loads(extra_raw)

        info = {}

        for item in extra:
            name = item.get("name")
            vals = item.get("vals", [])

            if not vals:
                continue

            if name in ("event_name", "event_type", "start_time", "lock_time"):
                info[name] = vals[0]

            if name == "action_event":
                try:
                    action_info = json.loads(vals[0])
                    info.update(action_info)
                except Exception:
                    pass

        event_name = str(info.get("event_name", "unknown"))
        event_type = str(info.get("event_type", "unknown"))
        start_time = float(info.get("start_time", 0))
        lock_time = float(info.get("lock_time", 0))
        duration = lock_time - start_time

        return {
            "event_name": event_name,
            "event_type": event_type,
            "start_time": start_time,
            "lock_time": lock_time,
            "duration": duration,
        }

    def _print_event(self, event):
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        print()
        print("=" * 64)
        print("收到动作回调")
        print("-" * 64)
        print(f"接收时间 : {now}")
        print(f"动作名称 : {event['event_name']}")
        print(f"动作类型 : {event['event_type']}")
        print(f"开始时间 : {event['start_time']:.3f} 秒")
        print(f"锁定时间 : {event['lock_time']:.3f} 秒")
        print(f"持续时间 : {event['duration']:.3f} 秒")
        print("=" * 64, flush=True)

    def _print_error(self, error):
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        print()
        print("=" * 64)
        print("收到回调，但解析失败")
        print("-" * 64)
        print(f"接收时间 : {now}")
        print(f"错误信息 : {error}")
        print("=" * 64, flush=True)

    def _reply_ok(self):
        body = b"OK"

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    server = HTTPServer((HOST, PORT), CallbackHandler)

    print("=" * 64)
    print("Callback HTTP Server 已启动")
    print("-" * 64)
    print(f"监听地址 : {HOST}:{PORT}")
    print("返回内容 : HTTP 200 OK")
    print("退出方式 : Ctrl+C")
    print("=" * 64, flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
        print("服务器已退出")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
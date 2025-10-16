#!/usr/bin/env python3
import asyncio
import json
import os
import csv
from datetime import datetime, timezone
from pathlib import Path

import websockets
from websockets.server import WebSocketServerProtocol

# ---- optional env ----
try:
    from dotenv import load_dotenv
    load_dotenv()
except Exception:
    pass

WS_HOST = os.getenv("WS_HOST", "0.0.0.0")
WS_PORT = int(os.getenv("WS_PORT", "8765"))

SERIAL_DEVICE = os.getenv("SERIAL_DEVICE", "")  # kosong => tidak forward
SERIAL_BAUD = int(os.getenv("SERIAL_BAUD", "115200"))

LOG_DIR = Path(os.getenv("LOG_DIR", "logs"))
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / "filtered_pose.csv"

# ---- serial (opsional) ----
_ser = None
if SERIAL_DEVICE:
    try:
        import serial
        _ser = serial.Serial(SERIAL_DEVICE, SERIAL_BAUD, timeout=0.2)
        print(f"[SERIAL] connected -> {SERIAL_DEVICE} @{SERIAL_BAUD}")
    except Exception as e:
        print(f"[SERIAL] failed to open {SERIAL_DEVICE}: {e}")
        _ser = None

# ---- helper waktu (UTC ISO-8601 ms + 'Z') ----
def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")

# ---- CSV init & compatibility (deteksi apakah header sudah punya acc_m) ----
_LOG_HAS_ACC = False
if LOG_FILE.exists():
    try:
        with open(LOG_FILE, "r", newline="", encoding="utf-8") as f:
            r = csv.reader(f)
            first = next(r, None)
            if isinstance(first, list) and "acc_m" in first:
                _LOG_HAS_ACC = True
    except Exception:
        pass
else:
    with open(LOG_FILE, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        # Pakai header baru yg mencakup acc_m
        w.writerow(["recv_at_iso", "lat", "lon", "heading_deg", "acc_m", "sent_at"])
        _LOG_HAS_ACC = True

def _validate_payload(d: dict) -> tuple[bool, str]:
    """
    expected:
    {
      'type': 'filtered_pose',
      'lat': float,
      'lon': float,
      'heading_deg': float,
      'sent_at': str(ISO-8601),
      'acc_m' | 'accuracy_m': optional float
    }
    """
    if not isinstance(d, dict):
        return False, "not a dict"
    if d.get("type") != "filtered_pose":
        return False, "invalid type"
    for k in ("lat", "lon", "heading_deg", "sent_at"):
        if k not in d:
            return False, f"missing {k}"
    try:
        float(d["lat"])
        float(d["lon"])
        float(d["heading_deg"])
    except Exception:
        return False, "lat/lon/heading must be float"
    # sent_at dibiarkan string (robust terhadap format)
    # acc_m / accuracy_m opsional
    return True, ""

def _log_to_csv(lat: float, lon: float, heading: float, sent_at: str, acc: float | None):
    with open(LOG_FILE, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if _LOG_HAS_ACC:
            w.writerow([now_iso(), f"{lat:.8f}", f"{lon:.8f}", f"{heading:.2f}", 
                        (f"{acc:.2f}" if isinstance(acc, (int, float)) else ""), sent_at])
        else:
            # kompatibel dgn file lama yg belum ada kolom acc_m
            w.writerow([now_iso(), f"{lat:.8f}", f"{lon:.8f}", f"{heading:.2f}", sent_at])

def _forward_serial(lat: float, lon: float, heading: float):
    if _ser and _ser.writable():
        # format sederhana CSV 1 baris, akhiri newline (mudah dibaca MCU/Arduino)
        line = f"{lat:.8f},{lon:.8f},{heading:.2f}\n"
        try:
            _ser.write(line.encode("utf-8"))
        except Exception as e:
            print(f"[SERIAL] write error: {e}")

async def _handle(ws: WebSocketServerProtocol):
    peer = ws.remote_address
    print(f"[WS] connected: {peer}")
    try:
        async for msg in ws:
            # terima hanya text frame JSON
            if isinstance(msg, (bytes, bytearray)):
                # abaikan biner
                continue

            try:
                data = json.loads(msg)
            except Exception:
                # abaikan pesan non-JSON
                continue

            ok, why = _validate_payload(data)
            if not ok:
                # kirim error ringan ke client (opsional)
                try:
                    await ws.send(json.dumps({"ack": False, "reason": why}))
                except Exception:
                    pass
                continue

            lat = float(data["lat"])
            lon = float(data["lon"])
            heading = float(data["heading_deg"])
            sent_at = str(data["sent_at"])

            # terima acc opsional: 'acc_m' atau 'accuracy_m'
            acc = data.get("acc_m", data.get("accuracy_m", None))
            try:
                acc = float(acc) if acc is not None else None
            except Exception:
                acc = None

            # tulis log lokal & forward serial (opsional)
            _log_to_csv(lat, lon, heading, sent_at, acc)
            _forward_serial(lat, lon, heading)

            # kirim ACK balik (bisa dipakai RTT / health-check)
            try:
                await ws.send(json.dumps({
                    "ack": True,
                    "received_at": now_iso(),
                    "orig_sent_at": sent_at,   # echo timestamp dari payload
                }))
            except Exception:
                # jika kirim ack gagal, biarkan loop lanjut
                pass

    except websockets.ConnectionClosed:
        # normal close
        pass
    except Exception as e:
        print(f"[WS] error from {peer}: {e}")
    finally:
        print(f"[WS] disconnected: {peer}")

async def main():
    print(f"[WS] listening on ws://{WS_HOST}:{WS_PORT}")
    # ping_interval/ping_timeout menjaga koneksi & mendeteksi putus
    async with websockets.serve(
        _handle,
        WS_HOST,
        WS_PORT,
        ping_interval=20,
        ping_timeout=20,
        max_size=2**20,         # 1 MB per message (lebih dari cukup)
        max_queue=64,           # batasi backlog
    ):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

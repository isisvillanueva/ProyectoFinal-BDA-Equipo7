"""
Escanea el iBeacon BLE y reporta el estado al backend del hospital.
Ejecutar en la laptop que tiene Bluetooth activo.

  pip install bleak aiohttp
  python beacon_scanner.py
"""
import asyncio
import struct
import time
import aiohttp
from datetime import datetime

BEACON_UUID      = "4E6ED5AB-B3ED-4E10-8247-C5F5524D4B21"
BEACON_MAJOR     = 12
BEACON_MINOR     = 13
BACKEND_URL      = "https://hermit-voter-effects.ngrok-free.dev"
SCRIPT_TOKEN     = "beacon_scanner_token_hospital7"
REPORT_INTERVAL  = 10   # segundos entre reportes al backend
BEACON_TIMEOUT   = 15   # segundos sin ver el beacon para marcarlo inactivo
SCANNER_RESTART  = 30   # reiniciar scanner cada N segundos (workaround macOS)

_ultimo_rssi: int | None = None
_ultima_deteccion: float = 0.0


def _parse_ibeacon(mfr: dict):
    for cid, data in mfr.items():
        if (cid == 0x004C and len(data) >= 23
                and data[0] == 0x02 and data[1] == 0x15):
            b = data[2:18]
            uuid = (
                f"{b[:4].hex()}-{b[4:6].hex()}-"
                f"{b[6:8].hex()}-{b[8:10].hex()}-{b[10:].hex()}"
            ).upper()
            major = struct.unpack(">H", data[18:20])[0]
            minor = struct.unpack(">H", data[20:22])[0]
            return uuid, major, minor
    return None


def _callback_deteccion(device, adv):
    global _ultimo_rssi, _ultima_deteccion
    parsed = _parse_ibeacon(adv.manufacturer_data)
    if not parsed:
        return
    uuid, major, minor = parsed
    if uuid == BEACON_UUID and major == BEACON_MAJOR and minor == BEACON_MINOR:
        rssi = getattr(adv, "rssi", None) or getattr(device, "rssi", -100)
        _ultimo_rssi = rssi
        _ultima_deteccion = time.monotonic()


async def _reportar(activo: bool, rssi=None):
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{BACKEND_URL}/api/beacon/heartbeat",
                json={
                    "token":       SCRIPT_TOKEN,
                    "uuid_beacon": BEACON_UUID,
                    "major":       BEACON_MAJOR,
                    "minor":       BEACON_MINOR,
                    "activo":      activo,
                    "rssi":        rssi,
                },
                timeout=aiohttp.ClientTimeout(total=5),
            ) as r:
                if r.status != 200:
                    text = await r.text()
                    print(f"  [!] Backend {r.status}: {text[:80]}")
    except Exception as e:
        print(f"  [!] Error al reportar: {e}")


async def _ciclo_reporte():
    while True:
        await asyncio.sleep(REPORT_INTERVAL)
        activo = (time.monotonic() - _ultima_deteccion) < BEACON_TIMEOUT
        ts = datetime.now().strftime("%H:%M:%S")
        if activo:
            print(f"[{ts}] detectado  RSSI={_ultimo_rssi} dBm")
            await _reportar(activo=True, rssi=_ultimo_rssi)
        else:
            print(f"[{ts}] no detectado")
            await _reportar(activo=False)


async def main():
    from bleak import BleakScanner

    print("Beacon Scanner — Hospital IoT")
    print(f"UUID  : {BEACON_UUID}")
    print(f"Major : {BEACON_MAJOR}  Minor: {BEACON_MINOR}")
    print(f"Backend: {BACKEND_URL}")
    print("─" * 50)

    asyncio.create_task(_ciclo_reporte())

    while True:
        async with BleakScanner(detection_callback=_callback_deteccion):
            await asyncio.sleep(SCANNER_RESTART)


if __name__ == "__main__":
    asyncio.run(main())

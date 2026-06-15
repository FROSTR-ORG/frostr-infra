#!/usr/bin/env python3
"""Black-box relay query helper for VAL-BACKUP-* assertions.

Connects to the demo dev relay (`ws://127.0.0.1:8194` from the host,
`ws://10.0.2.2:8194` from the Android emulator), sends a Nostr REQ
filtering by the share-derived backup author and kind-10000, and prints
the matching events in a stable form. The validator runs this script
with the share-derived author derived from a `bfshare1` package (use
`bifrost-devtools keygen share-info` or similar tooling) to confirm the
mobile app-published kind-10000 backup events are visible on the relay.

Exit codes:
- 0: relay returned at least one matching event
- 1: relay returned no events for the requested author/kind
- 2: relay connection failed
- 3: relay responded with a NOTICE/error frame
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Iterable

# Add the optional uv-installed `websockets` (`pip install websockets`)
# requirement gracefully below.

try:
    import websockets  # type: ignore
except ModuleNotFoundError as exc:  # pragma: no cover - install hint path
    sys.stderr.write(
        "This script requires the `websockets` Python package.\n"
        "Install with: pip install websockets\n"
        f"Original error: {exc}\n"
    )
    sys.exit(2)


async def query(relay: str, author_pubkey: str, kinds: Iterable[int]) -> list[dict]:
    subscription_id = f"verify-relay-backup-{int.from_bytes(__import__('os').urandom(4), 'big'):08x}"
    request = ["REQ", subscription_id, {"authors": [author_pubkey], "kinds": list(kinds)}]
    events: list[dict] = []
    notice: str | None = None

    async with websockets.connect(relay, open_timeout=10) as ws:
        await ws.send(json.dumps(request))
        while True:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=6)
            except asyncio.TimeoutError:
                break
            payload = json.loads(raw)
            verb = payload[0] if isinstance(payload, list) and payload else "?"
            if verb == "EVENT":
                events.append(payload[2])
            elif verb == "EOSE":
                break
            elif verb == "NOTICE":
                notice = payload[1] if len(payload) > 1 else "unknown"
                break
        await ws.send(json.dumps(["CLOSE", subscription_id]))

    if notice is not None:
        raise RuntimeError(f"relay NOTICE: {notice}")
    return events


def summarise(event: dict) -> str:
    return (
        f"id={event.get('id', '?')[:12]}… "
        f"pubkey={event.get('pubkey', '?')[:12]}… "
        f"kind={event.get('kind', '?')} "
        f"created_at={event.get('created_at', '?')}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--relay", default="ws://127.0.0.1:8194", help="relay websocket URL")
    parser.add_argument(
        "--author",
        required=True,
        help="share-derived x-only backup author pubkey (64-char hex)",
    )
    parser.add_argument(
        "--kinds",
        nargs="*",
        type=int,
        default=[10000],
        help="kind numbers to filter on (default: 10000)",
    )
    parser.add_argument(
        "--mode",
        choices=["latest", "count", "ids"],
        default="latest",
        help="output: latest=summarised most recent; count=event count; ids=one line per event id",
    )
    args = parser.parse_args()

    if len(args.author) != 64 or any(c not in "0123456789abcdef" for c in args.author.lower()):
        sys.stderr.write(
            f"--author must be a 64-char lowercase hex pubkey, got: {args.author!r}\n"
        )
        return 2

    try:
        events = asyncio.run(query(args.relay, args.author, args.kinds))
    except ConnectionRefusedError:
        sys.stderr.write(f"relay unreachable: {args.relay}\n")
        return 2
    except asyncio.TimeoutError:
        sys.stderr.write(f"relay timed out: {args.relay}\n")
        return 2
    except RuntimeError as exc:
        sys.stderr.write(f"relay error: {exc}\n")
        return 3

    if not events:
        sys.stderr.write(
            "no matching events on relay for "
            f"author={args.author[:12]}… kinds={args.kinds}\n"
        )
        return 1

    if args.mode == "count":
        print(len(events))
    elif args.mode == "ids":
        for event in sorted(events, key=lambda e: e.get("created_at", 0)):
            print(event.get("id", "?"))
    else:
        most_recent = max(events, key=lambda e: e.get("created_at", 0))
        print(f"matched_events={len(events)}")
        print(f"most_recent: {summarise(most_recent)}")
        if len(events) > 1:
            sys.stderr.write(
                f"(there are {len(events) - 1} older matching events on the relay; "
                "use --mode=ids or --mode=count to inspect)\n"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

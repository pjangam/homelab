#!/usr/bin/env python3
"""Run ON THE PI: reproduce nebula-sync's config step by hand and print the
replica's error body. GETs /api/config from xero, PATCHes it to the replica.
Reads passwords from ~/pihole-secondary.env; never prints them."""
import json, os, sys, urllib.request

env = dict(l.split("=", 1) for l in open(os.path.expanduser("~/pihole-secondary.env")).read().splitlines() if "=" in l)
pu, pp = env["PRIMARY"].split("|", 1)
ru, rp = env["REPLICAS"].split("|", 1)

def call(base, method, path, sid=None, body=None):
    req = urllib.request.Request(base + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"sid": sid} if sid else {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:2000]

def login(base, pw):
    return call(base, "POST", "/api/auth", body={"password": pw})[1]["session"]["sid"]

ps, rs = login(pu, pp), login(ru, rp)
try:
    _, cfg = call(pu, "GET", "/api/config", ps)
    conf = cfg["config"]
    keys = sys.argv[1:] or list(conf)
    for k in keys:
        st, body = call(ru, "PATCH", "/api/config", rs, {"config": {k: conf[k]}})
        print(k, st, "" if st == 200 else body)
finally:
    call(pu, "DELETE", "/api/auth", ps)
    call(ru, "DELETE", "/api/auth", rs)

#!/usr/bin/env python3
"""Probe anonymous song-URL protocols: weapi vs eapi."""
import base64
import json
import os
import secrets
import string
import urllib.parse
import urllib.request
import zlib

from Crypto.Cipher import AES

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

PRESET_KEY = b"0CoJUm6Qyw8W8jud"
SECRET = b"e82ckenh8dichen8"
PUBKEY = ("010001",
          "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7"
          "b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf69528"
          "01883bd0bbde106275a67a73cbbbde26c33bf084ab6a45b99eb46b57dee")
IV = b"0102030405060708"


def pad(data: bytes) -> bytes:
    n = 16 - len(data) % 16
    return data + bytes([n]) * n


def aes_ecb(key: bytes, text: bytes) -> bytes:
    c = AES.new(key, AES.MODE_ECB)
    return c.encrypt(pad(text))


def aes_cbc(key: bytes, iv: bytes, text: bytes) -> bytes:
    c = AES.new(key, AES.MODE_CBC, iv)
    return c.encrypt(pad(text))


def rsa_no_pad(text: bytes, exp: str, mod: str) -> str:
    # reverse then int pow mod, zero-padded to 128 bytes hex
    r = int.from_bytes(text[::-1], "big")
    m, e = int(mod, 16), int(exp, 16)
    v = pow(r, e, m)
    return "%0128x" % v


def weapi(text: dict) -> dict:
    rnd = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
    secret = rnd.encode()
    p1 = base64.b64encode(aes_cbc(PRESET_KEY, IV, json.dumps(text).encode())).decode()
    p2 = base64.b64encode(aes_cbc(secret.encode() if isinstance(secret, str) else secret,
                                  IV, p1.encode())).decode()
    enc_sec = rsa_no_pad(secret, PUBKEY[0], PUBKEY[1])
    return {"params": p2, "encSecKey": enc_sec}


def eapi(path: str, text: dict) -> tuple[bytes, str]:
    msg = json.dumps(text)
    digest = f"nobody{path}use{msg}md5forencrypt"
    sig = __import__("hashlib").md5(digest.encode()).hexdigest()
    data = f"{path}-36cd479b6b5-{msg}-36cd479b6b5-{sig}"
    enc = aes_ecb(SECRET, data.encode())
    return enc, sig


def post(url: str, body: bytes, headers: dict) -> bytes:
    req = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as r:
        out = r.read()
        print("   [http]", r.status, dict(r.headers).get("Content-Type"), "len", len(out), repr(out[:120]))
        if dict(r.headers).get("Content-Encoding") == "gzip":
            import gzip
            out = gzip.decompress(out)
        return out


def try_weapi(song_id=186016):
    path = "/api/song/enhance/player/url/v1"
    payload = {"ids": f"[{song_id}]", "level": "standard", "encodeType": "aac", "csrf_token": ""}
    form = weapi(payload)
    form["params"] = urllib.parse.quote(form["params"])
    form["encSecKey"] = urllib.parse.quote(form["encSecKey"])
    body = "&".join(f"{k}={v}" for k, v in form.items()).encode()
    hdr = {"User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded",
           "Referer": "https://music.163.com/"}
    out = post("https://music.163.com/weapi/song/enhance/player/url/v1?csrf_token=", body, hdr)
    return json.loads(out)


def try_eapi(song_id=186016):
    path = "/api/song/enhance/player/url"
    payload = {"ids": f"[{song_id}]", "br": 320000}
    enc, _ = eapi(path, payload)
    hdr = {"User-Agent": "Mozilla/5.0", "Content-Type": "application/x-www-form-urlencoded"}
    out = post("https://interface.music.163.com/eapi/song/enhance/player/url", enc, hdr)
    return json.loads(out)


if __name__ == "__main__":
    sid = int(os.environ.get("SID", "186016"))
    for name, fn in [("weapi-v1", lambda: try_weapi(sid)), ("eapi", lambda: try_eapi(sid))]:
        try:
            res = fn()
            d = res.get("data", [{}])[0] if isinstance(res.get("data"), list) else res
            print(name, "->", json.dumps({k: d.get(k) for k in ("id", "url", "br", "code", "level", "type")}, ensure_ascii=False)[:300])
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(name, "ERROR", repr(e))

def try_weapi_with_cookies(song_id=186016):
    import http.cookiejar
    import urllib.parse
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    req = urllib.request.Request("https://music.163.com/", headers={"User-Agent": UA})
    op.open(req, timeout=15).read()
    print("   [cookies]", [c.name for c in cj])
    path = "/api/song/enhance/player/url/v1"
    payload = {"ids": f"[{song_id}]", "level": "standard", "encodeType": "aac", "csrf_token": ""}
    form = weapi(payload)
    form["params"] = urllib.parse.quote(form["params"])
    form["encSecKey"] = urllib.parse.quote(form["encSecKey"])
    body = "&".join(f"{k}={v}" for k, v in form.items()).encode()
    hdr = {"User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded",
           "Referer": "https://music.163.com/", "Origin": "https://music.163.com"}
    req2 = urllib.request.Request("https://music.163.com/weapi/song/enhance/player/url/v1?csrf_token=",
                                  data=body, headers=hdr)
    with op.open(req2, timeout=15) as r:
        out = r.read()
        print("   [http2]", r.status, "len", len(out), repr(out[:120]))
        return json.loads(out) if out else {}

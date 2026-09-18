"""Live checks using SigV4 and Python's standard library; credentials stay in memory."""
import datetime
import hashlib
import hmac
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request


def read_json_command(args):
    return json.loads(subprocess.check_output(args, text=True))


def credentials():
    if os.environ.get("AWS_ACCESS_KEY_ID") and os.environ.get("AWS_SECRET_ACCESS_KEY"):
        return {"AccessKeyId": os.environ["AWS_ACCESS_KEY_ID"],
                "SecretAccessKey": os.environ["AWS_SECRET_ACCESS_KEY"],
                "SessionToken": os.environ.get("AWS_SESSION_TOKEN", "")}
    return read_json_command(["aws", "configure", "export-credentials", "--format", "process"])


def signed_headers(method, url, body, region, creds):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    day = stamp[:8]
    parsed = urllib.parse.urlsplit(url)
    headers = {"host": parsed.netloc, "x-amz-date": stamp, "content-type": "application/json"}
    if creds.get("SessionToken"):
        headers["x-amz-security-token"] = creds["SessionToken"]
    names = ";".join(sorted(headers))
    canonical_headers = "".join(f"{key}:{headers[key]}\n" for key in sorted(headers))
    canonical = "\n".join([method, parsed.path or "/", "", canonical_headers, names,
                            hashlib.sha256(body).hexdigest()])
    scope = f"{day}/{region}/execute-api/aws4_request"
    to_sign = "\n".join(["AWS4-HMAC-SHA256", stamp, scope,
                          hashlib.sha256(canonical.encode()).hexdigest()])
    key = ("AWS4" + creds["SecretAccessKey"]).encode()
    for value in [day, region, "execute-api", "aws4_request"]:
        key = hmac.new(key, value.encode(), hashlib.sha256).digest()
    signature = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    headers["Authorization"] = (f"AWS4-HMAC-SHA256 Credential={creds['AccessKeyId']}/{scope}, "
                                f"SignedHeaders={names}, Signature={signature}")
    return headers


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    outputs = read_json_command(["terraform", "output", "-json"])
    base = outputs["api_url"]["value"]
    region = outputs["region"]["value"]
    creds = credentials()

    def request(method, path, data=None, signed=True):
        time.sleep(1)  # Stay below this lab's API throttle.
        body = json.dumps(data).encode() if data is not None else b""
        url = base + path
        headers = signed_headers(method, url, body, region, creds) if signed else {}
        req = urllib.request.Request(url, data=body if data is not None else None,
                                     headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as result:
                return result.status, json.loads(result.read())
        except urllib.error.HTTPError as error:
            raw = error.read().decode()
            try:
                return error.code, json.loads(raw)
            except ValueError:
                return error.code, {"error": raw[:200]}

    def check(ok, message, result):
        if not ok:
            raise RuntimeError(f"{message}: {result}")
        print("PASS: " + message)

    print("Testing " + base)
    status, result = request("GET", "/tasks/example", signed=False)
    check(status == 403, "Anonymous request is blocked (403)", (status, result))
    status, result = request("POST", "/tasks", {"title": ""})
    check(status == 400, "Empty task title is rejected (400)", (status, result))
    task_id = None
    try:
        title = "Verify Terraform serverless lab"
        status, result = request("POST", "/tasks", {"title": title})
        task_id = result.get("id") if status == 201 else None
        check(status == 201 and bool(task_id), "Signed request creates a task (201)", (status, result))
        path = "/tasks/" + urllib.parse.quote(task_id, safe="")
        status, result = request("GET", path)
        check(status == 200 and result.get("title") == title and result.get("id") == task_id,
              "Stored task is retrieved correctly (200)", (status, result))
        status, result = request("DELETE", path)
        check(status == 200 and result.get("deleted") == task_id,
              "Task deletion succeeds (200)", (status, result))
        status, result = request("GET", path)
        check(status == 404, "Deleted task cannot be retrieved (404)", (status, result))
        task_id = None
    finally:
        if task_id:
            print("Removing the sample task after the interrupted test.")
            status, _ = request("DELETE", "/tasks/" + urllib.parse.quote(task_id, safe=""))
            if status != 200:
                print("Sample task remains; terraform destroy removes the lab table.")
    print("All six checks passed. AWS resources remain deployed until you run bash lab.sh delete.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        raise SystemExit(f"TEST FAILED: {error}\nResources remain deployed. Inspect the error before retrying.")

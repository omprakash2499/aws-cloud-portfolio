"""Small IAM-protected tasks API. The Lambda runtime provides boto3."""
import base64
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def response(status, body):
    return {"statusCode": status, "headers": {"content-type": "application/json"},
            "body": json.dumps(body)}


def handler(event, context):
    route = event.get("routeKey", "")
    if route == "POST /tasks":
        try:
            raw = event.get("body") or "{}"
            if event.get("isBase64Encoded"):
                raw = base64.b64decode(raw)
            data = json.loads(raw)
            title = data.get("title") if isinstance(data, dict) else None
            if not isinstance(title, str) or not 1 <= len(title.strip()) <= 120:
                return response(400, {"error": "title must contain 1-120 characters"})
        except (ValueError, TypeError):
            return response(400, {"error": "invalid JSON"})
        item = {"id": str(uuid.uuid4()), "title": title.strip(),
                "created_at": datetime.now(timezone.utc).isoformat()}
        table.put_item(Item=item)
        return response(201, item)
    task_id = (event.get("pathParameters") or {}).get("id")
    if not task_id:
        return response(404, {"error": "route not found"})
    if route == "GET /tasks/{id}":
        item = table.get_item(Key={"id": task_id}, ConsistentRead=True).get("Item")
        return response(200, item) if item else response(404, {"error": "task not found"})
    if route == "DELETE /tasks/{id}":
        table.delete_item(Key={"id": task_id})
        return response(200, {"deleted": task_id})
    return response(404, {"error": "route not found"})

"""Exercise Lambda request handling without AWS credentials or live services."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import Mock, patch


class HandlerTests(unittest.TestCase):
    def setUp(self):
        self.table = Mock()
        boto3 = Mock()
        boto3.resource.return_value.Table.return_value = self.table
        source = Path(__file__).resolve().parents[1] / "handler.py"
        spec = importlib.util.spec_from_file_location("lab_handler", source)
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict("sys.modules", {"boto3": boto3}), patch.dict(
            os.environ, {"TABLE_NAME": "unit-test-table"}
        ):
            spec.loader.exec_module(self.module)

    def call(self, event):
        result = self.module.handler(event, None)
        self.assertEqual(result["headers"]["content-type"], "application/json")
        return result["statusCode"], json.loads(result["body"])

    def test_create_trims_title_and_stores_returned_item(self):
        status, item = self.call({
            "routeKey": "POST /tasks", "body": json.dumps({"title": "  Read logs  "})
        })
        self.assertEqual(status, 201)
        self.assertEqual(item["title"], "Read logs")
        self.assertTrue(item["id"])
        self.assertTrue(item["created_at"])
        self.table.put_item.assert_called_once_with(Item=item)

    def test_invalid_titles_do_not_write_to_database(self):
        for title in (None, "", "   ", 42, [], "x" * 121):
            with self.subTest(title=title):
                status, _ = self.call({
                    "routeKey": "POST /tasks", "body": json.dumps({"title": title})
                })
                self.assertEqual(status, 400)
        self.table.put_item.assert_not_called()

    def test_invalid_json_and_non_object_bodies_are_rejected(self):
        for body in ("{", "[]", "null", "{}"):
            with self.subTest(body=body):
                status, _ = self.call({"routeKey": "POST /tasks", "body": body})
                self.assertEqual(status, 400)
        self.table.put_item.assert_not_called()

    def test_base64_encoded_json_can_create_task(self):
        body = base64.b64encode(b'{"title":"Check alarms"}').decode("ascii")
        status, item = self.call({
            "routeKey": "POST /tasks", "body": body, "isBase64Encoded": True
        })
        self.assertEqual(status, 201)
        self.assertEqual(item["title"], "Check alarms")

    def test_get_returns_existing_task(self):
        item = {"id": "task-1", "title": "Check alarms"}
        self.table.get_item.return_value = {"Item": item}
        status, body = self.call({
            "routeKey": "GET /tasks/{id}", "pathParameters": {"id": "task-1"}
        })
        self.assertEqual((status, body), (200, item))
        self.table.get_item.assert_called_once_with(
            Key={"id": "task-1"}, ConsistentRead=True
        )

    def test_missing_task_returns_404(self):
        self.table.get_item.return_value = {}
        status, _ = self.call({
            "routeKey": "GET /tasks/{id}", "pathParameters": {"id": "missing"}
        })
        self.assertEqual(status, 404)

    def test_delete_targets_requested_task(self):
        status, body = self.call({
            "routeKey": "DELETE /tasks/{id}", "pathParameters": {"id": "task-1"}
        })
        self.assertEqual((status, body), (200, {"deleted": "task-1"}))
        self.table.delete_item.assert_called_once_with(Key={"id": "task-1"})

    def test_unknown_route_and_missing_id_do_not_access_database(self):
        for event in ({}, {"routeKey": "GET /tasks/{id}"}, {
            "routeKey": "PATCH /tasks/{id}", "pathParameters": {"id": "task-1"}
        }):
            with self.subTest(event=event):
                status, _ = self.call(event)
                self.assertEqual(status, 404)
        self.assertEqual(self.table.mock_calls, [])


if __name__ == "__main__":
    unittest.main()

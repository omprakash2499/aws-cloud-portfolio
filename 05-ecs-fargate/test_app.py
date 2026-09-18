"""HTTP smoke tests; no AWS credentials needed by the Python client."""
import json
import sys
import time
import urllib.error
import urllib.request


def check(base):
    for attempt in range(12):
        try:
            with urllib.request.urlopen(base + '/health', timeout=5) as reply:
                assert reply.status == 200
                assert json.load(reply) == {'status': 'ok', 'service': 'ecs-lab'}
            break
        except (urllib.error.URLError, TimeoutError):
            if attempt == 11:
                raise
            time.sleep(5)
    print('PASS 1: Health endpoint returns HTTP 200 and expected JSON.')
    with urllib.request.urlopen(base + '/', timeout=5) as reply:
        assert reply.status == 200
        assert 'Running on ECS Fargate' in reply.read().decode()
    print('PASS 2: Homepage returns expected application content.')
    try:
        urllib.request.urlopen(base + '/missing', timeout=5)
    except urllib.error.HTTPError as error:
        assert error.code == 404
    else:
        raise AssertionError('Unknown path did not return 404')
    print('PASS 3: Unknown path returns HTTP 404.')


if __name__ == '__main__':
    check(sys.argv[1].rstrip('/'))

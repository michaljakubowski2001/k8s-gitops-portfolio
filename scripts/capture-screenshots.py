"""Capture the local kind cluster's UIs with a locally installed Chrome browser.

Needs `kubectl -n argocd port-forward svc/argocd-server 8081:80` running and
the cluster bootstrapped with scripts/bootstrap.sh.
"""
import base64
import json
import subprocess
from pathlib import Path

from playwright.sync_api import sync_playwright

output = Path('docs/screenshots')
output.mkdir(parents=True, exist_ok=True)
secret = json.loads(subprocess.check_output(
    ['kubectl', '-n', 'argocd', 'get', 'secret', 'argocd-initial-admin-secret', '-o', 'json']))
argocd_password = base64.b64decode(secret['data']['password']).decode()

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel='chrome', headless=True)
    page = browser.new_page(viewport={'width': 1440, 'height': 1000}, device_scale_factor=1)

    page.goto('http://localhost:8081/login', wait_until='networkidle')
    page.fill('input[name="username"]', 'admin')
    page.fill('input[name="password"]', argocd_password)
    page.click('button[type="submit"]')
    page.wait_for_url('**/applications**')
    for name, url in [
        ('argocd-apps', 'http://localhost:8081/applications'),
        ('argocd-root-tree', 'http://localhost:8081/applications/argocd/root?view=tree&resource='),
        ('grafana', 'http://grafana.localhost:8080/d/k8s-gitops-platform?orgId=1&from=now-30m&to=now&kiosk'),
        ('uptime-kuma', 'http://status.localhost:8080/status/portfolio'),
    ]:
        response = page.goto(url, wait_until='networkidle', timeout=60000)
        if not response or response.status != 200:
            raise RuntimeError(f'{name}: unexpected response')
        page.wait_for_timeout(8000)
        page.screenshot(path=str(output / f'{name}.png'), full_page=name != 'argocd-root-tree')
        print(f'{name}: {page.title()}')
    browser.close()

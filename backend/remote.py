import argparse
import getpass
import json
import os
import posixpath
import shutil
import socket
import subprocess
import time
import uuid
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import requests

try:
    import paramiko
except ImportError:
    paramiko = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Qwen-VL inference from another computer with local image upload via SSH"
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8000", help="API base URL (typically via SSH tunnel)")
    parser.add_argument("--model", default="Qwen-VL-Chat-Int4", help="Model id for /v1/chat/completions payload")
    parser.add_argument("--question", required=True, help="Question text for the image")

    parser.add_argument("--image", default="", help="Local image path on this computer")
    parser.add_argument("--remote-image-path", default="", help="Image path that already exists on server")

    parser.add_argument("--ssh-host", default="", help="SSH host for uploading image")
    parser.add_argument("--ssh-port", type=int, default=22, help="SSH port")
    parser.add_argument("--ssh-user", default="", help="SSH username")
    parser.add_argument("--ssh-password", default="410329", help="SSH password (or omit and interactive input)")
    parser.add_argument("--ssh-key", default="", help="SSH private key file path")
    parser.add_argument("--remote-upload-dir", default="/tmp/qwenvl_uploads", help="Remote upload directory")
    parser.add_argument("--cleanup-remote", action="store_true", help="Delete uploaded remote image after inference")
    parser.add_argument("--auto-tunnel", action="store_true", help="Automatically create ssh -N -L tunnel in this script")
    parser.add_argument("--remote-forward-host", default="127.0.0.1", help="Remote host for SSH -L target")
    parser.add_argument("--remote-forward-port", type=int, default=8000, help="Remote port for SSH -L target")
    parser.add_argument("--tunnel-ready-timeout", type=int, default=20, help="Seconds to wait for local forwarded port")

    parser.add_argument("--temperature", type=float, default=1.0, help="Sampling temperature")
    parser.add_argument("--top-p", type=float, default=0.8, help="Nucleus sampling top-p in (0,1]")
    parser.add_argument("--max-tokens", type=int, default=512, help="Max tokens for generation")
    parser.add_argument("--timeout", type=int, default=300, help="HTTP timeout seconds")
    return parser.parse_args()


def _open_ssh_client(args: argparse.Namespace):
    if paramiko is None:
        raise RuntimeError("paramiko is required. Install with: pip install paramiko")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    connect_kwargs = {
        "hostname": args.ssh_host,
        "port": args.ssh_port,
        "username": args.ssh_user,
        "timeout": 30,
    }

    if args.ssh_key:
        connect_kwargs["key_filename"] = args.ssh_key
    else:
        password = args.ssh_password or getpass.getpass(f"SSH password for {args.ssh_user}@{args.ssh_host}: ")
        connect_kwargs["password"] = password

    client.connect(**connect_kwargs)
    return client


def _wait_local_port_ready(host: str, port: int, timeout_seconds: int) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.connect((host, port))
            return True
        except OSError:
            time.sleep(0.2)
        finally:
            sock.close()
    return False


def start_ssh_tunnel(args: argparse.Namespace) -> subprocess.Popen:
    if not args.ssh_host or not args.ssh_user:
        raise ValueError("--ssh-host and --ssh-user are required when using --auto-tunnel")

    ssh_binary = shutil.which("ssh")
    if not ssh_binary:
        raise RuntimeError("ssh executable not found. Please install OpenSSH client first")

    parsed = urlparse(args.base_url)
    local_host = parsed.hostname or "127.0.0.1"
    local_port = parsed.port or 8000

    forward_spec = f"{local_port}:{args.remote_forward_host}:{args.remote_forward_port}"
    command = [
        ssh_binary,
        "-N",
        "-L",
        forward_spec,
        "-p",
        str(args.ssh_port),
    ]
    if args.ssh_key:
        command.extend(["-i", args.ssh_key])
    command.append(f"{args.ssh_user}@{args.ssh_host}")

    process = subprocess.Popen(command)
    if not _wait_local_port_ready(local_host, local_port, args.tunnel_ready_timeout):
        process.terminate()
        raise RuntimeError(
            "SSH tunnel not ready in time. Check SSH auth, host reachability, and local port usage"
        )
    return process


def upload_image_via_ssh(args: argparse.Namespace) -> str:
    local_path = Path(args.image).expanduser().resolve()
    if not local_path.exists():
        raise FileNotFoundError(f"Local image not found: {local_path}")

    if not args.ssh_host or not args.ssh_user:
        raise ValueError("--ssh-host and --ssh-user are required when using --image upload mode")

    client = _open_ssh_client(args)
    sftp = client.open_sftp()
    try:
        try:
            sftp.stat(args.remote_upload_dir)
        except FileNotFoundError:
            sftp.mkdir(args.remote_upload_dir)

        suffix = local_path.suffix or ".jpg"
        remote_filename = f"{uuid.uuid4().hex}{suffix}"
        remote_path = posixpath.join(args.remote_upload_dir, remote_filename)
        sftp.put(str(local_path), remote_path)
        return remote_path
    finally:
        sftp.close()
        client.close()


def cleanup_remote_file(args: argparse.Namespace, remote_path: str) -> None:
    if not args.cleanup_remote:
        return
    client = _open_ssh_client(args)
    try:
        command = f"rm -f '{remote_path}'"
        client.exec_command(command)
    finally:
        client.close()


def run_inference(args: argparse.Namespace, remote_image_path: str) -> dict:
    query = f"<img>{remote_image_path}</img>\n{args.question}"
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": query}],
        "temperature": args.temperature,
        "top_p": args.top_p,
        "max_tokens": args.max_tokens,
        "stream": False,
    }
    endpoint = f"{args.base_url.rstrip('/')}/v1/chat/completions"
    response = requests.post(endpoint, json=payload, timeout=args.timeout)
    if response.status_code >= 400:
        body = response.text[:2000]
        raise RuntimeError(
            f"API request failed: status={response.status_code}, body={body}"
        )
    return response.json()


def check_server_health(args: argparse.Namespace) -> None:
    endpoint = f"{args.base_url.rstrip('/')}/v1/models"
    try:
        response = requests.get(endpoint, timeout=min(args.timeout, 30))
    except Exception as exception:
        raise RuntimeError(
            "Failed to connect API server. Ensure server is running and SSH tunnel is ready"
        ) from exception

    if response.status_code >= 400:
        body = response.text[:2000]
        raise RuntimeError(
            f"API health check failed: status={response.status_code}, body={body}"
        )


def extract_text(result: dict) -> str:
    try:
        return result["choices"][0]["message"]["content"]
    except Exception:
        return json.dumps(result, ensure_ascii=False)


def main() -> None:
    args = parse_args()

    if bool(args.image) == bool(args.remote_image_path):
        raise ValueError("Provide exactly one of --image or --remote-image-path")

    uploaded_remote_path: Optional[str] = None
    tunnel_process: Optional[subprocess.Popen] = None
    try:
        if args.auto_tunnel:
            tunnel_process = start_ssh_tunnel(args)
            print("ssh_tunnel_ready")

        if args.remote_image_path:
            remote_image_path = args.remote_image_path
        else:
            uploaded_remote_path = upload_image_via_ssh(args)
            remote_image_path = uploaded_remote_path
            print(f"uploaded_remote_image={remote_image_path}")

        check_server_health(args)
        print("api_server_ready")

        result = run_inference(args, remote_image_path)
        print("response:")
        print(extract_text(result))
    finally:
        if uploaded_remote_path:
            cleanup_remote_file(args, uploaded_remote_path)
        if tunnel_process is not None and tunnel_process.poll() is None:
            tunnel_process.terminate()


if __name__ == "__main__":
    main()

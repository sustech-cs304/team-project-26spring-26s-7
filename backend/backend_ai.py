import argparse
import json
from pathlib import Path

import requests


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="HTTP image client for Qwen-VL backend (no SSH required)")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000", help="API base URL")
    parser.add_argument("--image", required=True, help="Local image path")
    parser.add_argument("--question", required=True, help="Question text")
    parser.add_argument("--model", default="Qwen-VL-Chat-Int4", help="Model name to attach in response")
    parser.add_argument("--temperature", type=float, default=1.0, help="Sampling temperature")
    parser.add_argument("--top-p", type=float, default=0.8, help="Sampling top-p")
    parser.add_argument("--timeout", type=int, default=300, help="Request timeout seconds")
    return parser.parse_args()


def extract_text(response_json: dict) -> str:
    try:
        return response_json["choices"][0]["message"]["content"]
    except Exception:
        return json.dumps(response_json, ensure_ascii=False)


def main() -> None:
    args = parse_args()

    image_path = Path(args.image).expanduser().resolve()
    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    endpoint = f"{args.base_url.rstrip('/')}/v1/chat/completions/image"
    with image_path.open("rb") as image_file:
        files = {
            "image": (image_path.name, image_file, "application/octet-stream"),
        }
        data = {
            "model_name": args.model,
            "question": args.question,
            "temperature": str(args.temperature),
            "top_p": str(args.top_p),
        }
        response = requests.post(endpoint, files=files, data=data, timeout=args.timeout)

    if response.status_code >= 400:
        raise RuntimeError(f"API request failed: status={response.status_code}, body={response.text[:2000]}")

    result = response.json()
    print("response:")
    print(extract_text(result))


if __name__ == "__main__":
    main()
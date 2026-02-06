"""
Optional Gradio chat UI (requires separate venv: gradio conflicts with pydantic-ai).
Preferred: run the API and open http://localhost:8000/chat-ui in your browser (no extra deps).
"""
import os

import httpx

# Default: backend running locally
CHAT_URL = os.environ.get("CHAT_URL", "http://localhost:8000/chat")


def chat(message: str, history: list, session_id: str | None) -> tuple[list, str | None]:
    """Send message to backend, return (updated history, session_id)."""
    payload = {"message": message}
    if session_id:
        payload["session_id"] = session_id
    try:
        r = httpx.post(CHAT_URL, json=payload, timeout=60.0)
        r.raise_for_status()
        data = r.json()
        response = data.get("response", "")
        new_sid = data.get("session_id")
    except httpx.HTTPStatusError as e:
        response = f"API error {e.response.status_code}: {e.response.text[:500]}"
        new_sid = session_id
    except Exception as e:
        response = f"Error: {e}"
        new_sid = session_id
    history = history + [(message, response)]
    return history, new_sid


def main():
    import gradio as gr

    print(f"Chat UI → {CHAT_URL}")
    session_id = gr.State(None)

    with gr.Blocks(title="Resy Agent – Test Chat", css="footer {display: none !important}") as demo:
        gr.Markdown("## Resy booking agent – test UI\nChat with the agent. Session is kept so context is preserved.")
        chatbot = gr.Chatbot(label="Chat", height=400)
        msg = gr.Textbox(placeholder="Ask for hotspots, availability, or book...", label="Message", scale=7)
        submit = gr.Button("Send", scale=1)

        def respond(message, history, sid):
            if not (message or "").strip():
                return history, sid
            new_history, new_sid = chat(message.strip(), history, sid)
            return new_history, new_sid

        msg.submit(respond, [msg, chatbot, session_id], [chatbot, session_id])
        submit.click(respond, [msg, chatbot, session_id], [chatbot, session_id])
        msg.submit(lambda: "", None, [msg])

    demo.launch(server_name="127.0.0.1", server_port=7860)


if __name__ == "__main__":
    main()

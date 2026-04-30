"""
runway/notifier.py

Formats and sends Slack notifications for pipeline health reports.
"""
from __future__ import annotations

from datetime import datetime

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

from .config import RunwayConfig
from .predictor import BreachPrediction
from .rules import Recommendation, Severity


SEVERITY_EMOJI = {
    Severity.OK: ":white_check_mark:",
    Severity.INFO: ":information_source:",
    Severity.WARNING: ":warning:",
    Severity.CRITICAL: ":rotating_light:",
}


def send_alert(
    prediction: BreachPrediction,
    recommendation: Recommendation,
    channel: str | None = None,
) -> None:
    """Send a Slack message for a pipeline health report."""
    config = RunwayConfig.load()
    target_channel = channel or config.slack_channel

    if not config.slack_token:
        raise ValueError("SLACK_TOKEN not configured in runway.yaml or environment")

    client = WebClient(token=config.slack_token)
    blocks = _build_blocks(prediction, recommendation)

    try:
        client.chat_postMessage(
            channel=target_channel,
            text=f"[Runway] {prediction.job_name} — {recommendation.action}",
            blocks=blocks,
        )
    except SlackApiError as e:
        raise RuntimeError(f"Slack notification failed: {e.response['error']}") from e


def _build_blocks(
    prediction: BreachPrediction,
    recommendation: Recommendation,
) -> list[dict]:
    emoji = SEVERITY_EMOJI.get(recommendation.severity, ":information_source:")
    header = f"{emoji} *[Runway] {prediction.job_name}*"

    fields = [
        f"*P95 latency:* {prediction.current_p95_s}s",
        f"*Trend:* {prediction.trend_pct_per_week:+.1f}%/week",
        f"*SLA threshold:* {prediction.sla_threshold_s}s",
        f"*Runs analysed:* {prediction.runs_used}",
    ]

    if prediction.breach_days is not None:
        breach_str = (
            f"{prediction.breach_days} days "
            f"(±{prediction.confidence_days} days, 80% CI)"
        )
        if prediction.breach_date:
            breach_str += f" — {prediction.breach_date.strftime('%d %b %Y')}"
        fields.append(f"*Breach in:* {breach_str}")

    recommendation_text = (
        f"*{recommendation.title}*\n{recommendation.body}"
    )

    return [
        {"type": "section", "text": {"type": "mrkdwn", "text": header}},
        {"type": "divider"},
        {
            "type": "section",
            "fields": [{"type": "mrkdwn", "text": f} for f in fields],
        },
        {
            "type": "section",
            "text": {"type": "mrkdwn", "text": recommendation_text},
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": (
                        f"Runway · {datetime.utcnow().strftime('%d %b %Y %H:%M')} UTC · "
                        f"<{recommendation.docs_url}|Docs>"
                    ),
                }
            ],
        },
    ]

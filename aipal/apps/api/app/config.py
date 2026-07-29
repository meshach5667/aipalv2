from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite+aiosqlite:///./instance/app.db"
    database_path: str = "./instance/app.db"
    jwt_secret: str = "dev-secret-change-in-production"
    jwt_expire_minutes: int = 60 * 24 * 7
    jwt_refresh_days: int = 30
    aipal_env: str = "development"
    magic_link_dev_return_token: bool = True
    litestream_s3_bucket: str = ""
    litestream_s3_endpoint: str = ""
    litestream_s3_region: str = "us-east-1"
    litestream_access_key_id: str = ""
    litestream_secret_access_key: str = ""
    gunicorn_workers: int = 4
    gunicorn_bind: str = "0.0.0.0:8102"

    llm_provider: str = "gemini"
    gemini_api_key: str = ""
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta/openai"
    gemini_model: str = "gemini-2.0-flash"
    gemini_timeout_seconds: float = 18.0
    gemini_max_tokens: int = 220
    # "base" is the minimum production default for accent/noise robustness.
    # Use WHISPER_MODEL=tiny only for low-resource local demos.
    whisper_model: str = "base"
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    whisper_beam_size: int = 5
    max_audio_decode_seconds: int = 12
    tts_provider: str = "edge"
    tts_timeout_seconds: float = 6.0
    stt_provider: str = "whisper_stream"
    whisper_stream_partial_interval_ms: int = 150
    stt_min_confidence: float = 0.28
    stt_max_no_speech_probability: float = 0.78
    stt_min_final_chars: int = 2
    live_voice_v2: bool = True
    live_voice_transport: str = "websocket_pcm"
    realtime_voice_provider: str = ""
    live_turns_per_minute: int = 20
    mem0_enabled: bool = False
    redis_url: str = ""
    context_cache_ttl_seconds: int = 180
    notification_dispatcher_enabled: bool = True
    notification_dispatcher_interval_seconds: int = 30
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = "noreply@aipal.local"
    smtp_use_tls: bool = True
    email_notifications_provider: str = "smtp"
    cors_origins: str = "*"
    spotify_client_id: str = ""
    spotify_client_secret: str = ""
    spotify_redirect_uri: str = "aipal://spotify-callback"


@lru_cache
def get_settings() -> Settings:
    return Settings()

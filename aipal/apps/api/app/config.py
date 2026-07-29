from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", populate_by_name=True)

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

    llm_provider: str = "deepseek"
    deepseek_api_key: str = ""
    deepseek_timeout_seconds: float = 120.0
    deepseek_max_tokens: int = 8192
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    openai_model: str = "gpt-4o-mini"
    openai_timeout_seconds: float = 18.0
    openai_max_tokens: int = 220
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "llama3.2:3b"
    ollama_num_predict: int = 72
    ollama_temperature: float = 0.2
    ollama_timeout_seconds: float = 12.0
    # "base" is the minimum production default for accent/noise robustness.
    # Use WHISPER_MODEL=tiny only for low-resource local demos.
    whisper_model: str = "base"
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    whisper_beam_size: int = 5
    max_audio_decode_seconds: int = 12
    tts_provider: str = "edge"
    speech_tts_provider: str = ""
    tts_timeout_seconds: float = 6.0
    fish_api_key: str = ""
    fish_audio_api_key: str = Field(default="", validation_alias="FISH_AUDIO_API_KEY")
    fish_base_url: str = "https://api.fish.audio"
    fish_audio_base_url: str = Field(default="", validation_alias="FISH_AUDIO_BASE_URL")
    fish_tts_model: str = "s2-pro"
    fish_audio_tts_model: str = Field(default="", validation_alias="FISH_AUDIO_TTS_MODEL")
    fish_tts_reference_id: str = ""
    fish_audio_voice_id: str = Field(default="", validation_alias="FISH_AUDIO_VOICE_ID")
    fish_tts_latency: str = "normal"
    fish_audio_asr_model: str = Field(default="", validation_alias="FISH_AUDIO_ASR_MODEL")
    stt_provider: str = "whisper_stream"
    speech_stt_provider: str = ""
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

    @property
    def effective_tts_provider(self) -> str:
        provider = (self.speech_tts_provider or self.tts_provider or "edge").lower()
        return "fish" if provider in {"fish_audio", "fish-audio"} else provider

    @property
    def effective_stt_provider(self) -> str:
        provider = (self.speech_stt_provider or self.stt_provider or "whisper_stream").lower()
        return "fish_audio" if provider in {"fish", "fish-audio"} else provider

    @property
    def effective_fish_api_key(self) -> str:
        return self.fish_audio_api_key or self.fish_api_key

    @property
    def effective_fish_base_url(self) -> str:
        return self.fish_audio_base_url or self.fish_base_url

    @property
    def effective_fish_tts_model(self) -> str:
        return self.fish_audio_tts_model or self.fish_tts_model

    @property
    def effective_fish_asr_model(self) -> str:
        return self.fish_audio_asr_model or "s1"

    @property
    def effective_fish_voice_id(self) -> str:
        return self.fish_audio_voice_id or self.fish_tts_reference_id


@lru_cache
def get_settings() -> Settings:
    return Settings()

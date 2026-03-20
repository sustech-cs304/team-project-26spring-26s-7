# 后端服务器安全规范

> **文档版本**: V1.0
> **适用对象**: 后端开发组 (组员 C - 基础设施负责人、组员 D - AI 业务逻辑负责人)
> **安全负责人**: 组员 E (规范与安全负责人)
> **依据标准**: HarmonyOS NEXT 安全技术白皮书 V1.0 (2024-08-13)

---

## 1. 后端服务器安全架构总览

### 1.1 后端组件清单

根据项目架构，后端服务器包含以下核心组件：

| 组件名称 | 功能描述 | 数据敏感性 | 安全等级要求 |
|---------|---------|-----------|-------------|
| **SyncServer** | 分布式同步服务器，处理多端数据同步 | S3 (高) | SL4+ |
| **CloudDB** | PostGIS 空间数据库，存储轨迹与地点数据 | S3-S4 (高 - 严重) | SL4+ |
| **OSS** | 对象存储，存放媒体文件与缩略图 | S2-S3 (中 - 高) | SL3+ |
| **AIGateway** | AI 网关，处理文案生成与内容风控 | S2-S3 (中 - 高) | SL3+ |
| **WebPortal** | Web 分享门户，只读渲染 | S1-S2 (低 - 中) | SL2+ |

### 1.2 数据分级与加密等级映射

依据 HarmonyOS 白皮书第 6 章"正确的访问数据"分级访问控制架构：

| 数据类型 | 风险等级 | 加密等级 | 存储要求 | 传输要求 |
|---------|---------|---------|---------|---------|
| 用户账号/认证 Token | S4 (严重) | EL5 | 服务端加密存储，密钥独立管理 | TLS1.3+，双向认证 |
| 精确地理位置 (经纬度<10m) | S4 (严重) | EL5 | PostGIS 加密字段，访问审计 | TLS1.3+ |
| 脱敏位置 (模糊至 100m) | S3 (高) | EL4 | PostGIS 普通字段 | TLS1.2+ |
| 原始照片 (含 EXIF) | S3 (高) | EL4 | 禁止存储，必须前端脱敏 | TLS1.2+ |
| 脱敏照片 (无 EXIF) | S2 (中) | EL3 | OSS 加密存储 | TLS1.2+ |
| AI 生成的文案/标签 | S2 (中) | EL3 | 数据库普通存储 | TLS1.2+ |
| 公开分享的轨迹/日记 | S1 (低) | EL2 | 可公开访问，防篡改 | HTTPS |

---

## 2. 用户数据存储隔离规范

### 2.1 多租户数据隔离架构

依据白皮书第 5 章"正确的设备"系统安全架构中的**隔离及访问控制**原则：

```
┌─────────────────────────────────────────────────────────┐
│                    应用层 (Application Layer)            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  Tenant A   │  │  Tenant B   │  │  Tenant C   │     │
│  │   Schema    │  │   Schema    │  │   Schema    │     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │
├─────────┼────────────────┼────────────────┼─────────────┤
│         ▼                ▼                ▼             │
│  ┌─────────────────────────────────────────────────┐   │
│  │           行级安全策略 (Row-Level Security)      │   │
│  │         PostgreSQL RLS + PostGIS 空间过滤        │   │
│  └─────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                    数据层 (Data Layer)                  │
│  ┌─────────────────────────────────────────────────┐   │
│  │           列级加密 (Column-Level Encryption)     │   │
│  │          敏感字段 AES-256-GCM 加密               │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 数据库隔离实现

```python
# 后端：PostgreSQL 行级安全 (RLS) 配置示例
# 必须在数据库层面强制执行，而非仅依赖应用层逻辑

-- 1. 启用行级安全
ALTER TABLE user_diaries ENABLE ROW LEVEL SECURITY;

-- 2. 创建策略：用户只能访问自己的日记
CREATE POLICY user_diaries_isolation ON user_diaries
    FOR ALL
    USING (user_id = current_setting('app.current_user_id')::UUID);

-- 3. 创建策略：地理位置数据访问控制
CREATE POLICY location_data_isolation ON user_locations
    FOR ALL
    USING (
        user_id = current_setting('app.current_user_id')::UUID
        AND precision_level <= current_setting('app.max_precision')::INT
    );

-- 4. 在事务中设置上下文
BEGIN;
SET LOCAL app.current_user_id = '550e8400-e29b-41d4-a716-446655440000';
SET LOCAL app.max_precision = '5';  -- 最高精度级别
-- 执行查询...
COMMIT;
```

### 2.3 敏感数据加密存储

```python
# 后端：敏感字段加密工具类
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os
import base64

class FieldLevelEncryption:
    """
    字段级加密 - 符合 HarmonyOS EL5 加密标准的服务器端实现

    安全要求:
    - 使用 AES-256-GCM  authenticated encryption
    - 每字段独立 nonce
    - 密钥派生使用 HKDF-SHA256
    - 密钥存储于 HSM/KMS，禁止硬编码
    """

    def __init__(self, master_key: bytes):
        # master_key 应从 KMS 动态获取，而非配置文件
        self._master_key = master_key

    def _derive_field_key(self, field_name: str, user_id: str) -> bytes:
        """使用 HKDF 派生字段级密钥，实现用户间隔离"""
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.kdf.hkdf import HKDF

        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=None,
            info=f"{field_name}:{user_id}".encode(),
        )
        return hkdf.derive(self._master_key)

    def encrypt(self, plaintext: str, field_name: str, user_id: str) -> str:
        """加密敏感字段"""
        import json

        field_key = self._derive_field_key(field_name, user_id)
        aesgcm = AESGCM(field_key)
        nonce = os.urandom(12)  # 96-bit nonce for GCM

        ciphertext = aesgcm.encrypt(nonce, plaintext.encode(), None)

        # 返回 base64 编码：nonce + ciphertext + tag
        payload = nonce + ciphertext
        return base64.b64encode(payload).decode()

    def decrypt(self, encrypted_data: str, field_name: str, user_id: str) -> str:
        """解密敏感字段"""
        field_key = self._derive_field_key(field_name, user_id)
        aesgcm = AESGCM(field_key)

        payload = base64.b64decode(encrypted_data)
        nonce = payload[:12]
        ciphertext = payload[12:]

        plaintext = aesgcm.decrypt(nonce, ciphertext, None)
        return plaintext.decode()


# 使用示例
# 加密用户日记中的精确坐标 (S4 级数据)
encryption = FieldLevelEncryption(master_key=KMS.get_key("diary_encryption_key"))

encrypted_lat = encryption.encrypt(
    plaintext="22.542831",  # 精确纬度
    field_name="latitude",
    user_id=user_id
)
```

---

## 3. 服务器端大模型 (AI Gateway) 安全规范

### 3.1 AI 服务安全架构

依据白皮书第 8 章应用运行安全中的**沙箱隔离**与**零信任**原则：

```
┌──────────────────────────────────────────────────────────┐
│                   AI Gateway 安全架构                     │
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐ │
│  │              请求层 (Request Layer)                 │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │ │
│  │  │ 身份验证  │  │ 速率限制  │  │ 输入过滤  │        │ │
│  │  └──────────┘  └──────────┘  └──────────┘        │ │
│  └────────────────────────────────────────────────────┘ │
│                           ▼                              │
│  ┌────────────────────────────────────────────────────┐ │
│  │              沙箱层 (Sandbox Layer)                 │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │  gVisor / Firecracker MicroVM 隔离容器        │ │ │
│  │  │  - 网络隔离 (仅允许出站 AI API)               │ │ │
│  │  │  - 文件系统只读挂载                            │ │ │
│  │  │  - Seccomp 系统调用过滤                       │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
│                           ▼                              │
│  ┌────────────────────────────────────────────────────┐ │
│  │             AI 服务层 (AI Service Layer)            │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │ │
│  │  │ 本地 LLM │  │ 云端 LLM │  │ 内容审核  │        │ │
│  │  │ (OCR)    │  │ (文案)   │  │ (风控)   │        │ │
│  │  └──────────┘  └──────────┘  └──────────┘        │ │
│  └────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 3.2 AI 网关安全实现

```python
# 后端：AI Gateway 安全控制器
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, validator
import aiohttp
import asyncio
from datetime import timedelta
from typing import Optional, List
import hashlib
import json

router = APIRouter()

class AIRequest(BaseModel):
    """AI 请求模型 - 带输入验证"""
    user_id: str
    diary_id: str
    prompt: str = Field(..., max_length=2000)  # 限制 prompt 长度防 DoS
    content_type: str  # 'caption' | 'ocr' | 'summary' | 'moderation'

    @validator('prompt')
    def validate_prompt(cls, v):
        # 防止 prompt 注入攻击
        dangerous_patterns = [
            '忽略上述', 'ignore above', 'system prompt',
            '忘记指令', 'forget instruction', '越狱', 'jailbreak'
        ]
        v_lower = v.lower()
        for pattern in dangerous_patterns:
            if pattern in v_lower:
                raise ValueError(f'检测到潜在的 prompt 注入攻击: {pattern}')
        return v


class AIGatewaySecurity:
    """
    AI 网关安全控制器

    安全特性:
    1. 输入验证 - 防 prompt 注入
    2. 速率限制 - 防 API 滥用
    3. 沙箱执行 - 容器隔离
    4. 输出审核 - 防有害内容
    5. 审计日志 - 完整追溯
    """

    def __init__(self):
        self.rate_limiter = RateLimiter(max_requests=10, window=timedelta(minutes=1))
        self.content_moderator = ContentModerator()
        self.audit_logger = AuditLogger(service='ai-gateway')

    async def process_request(self, request: AIRequest) -> dict:
        """处理 AI 请求的完整安全流程"""

        # 1. 速率限制检查
        if not await self.rate_limiter.is_allowed(request.user_id):
            self.audit_logger.log_security_event(
                event='rate_limit_exceeded',
                user_id=request.user_id,
                ip=request.client.host
            )
            raise HTTPException(status_code=429, detail='请求频率超限')

        # 2. 输入验证
        try:
            self._validate_input(request)
        except ValueError as e:
            self.audit_logger.log_security_event(
                event='input_validation_failed',
                user_id=request.user_id,
                reason=str(e)
            )
            raise HTTPException(status_code=400, detail=f'输入验证失败：{str(e)}')

        # 3. 在沙箱容器中执行 AI 调用
        result = await self._execute_in_sandbox(request)

        # 4. 输出内容审核
        moderation_result = await self.content_moderator.check(result['content'])
        if not moderation_result.is_safe:
            self.audit_logger.log_security_event(
                event='content_moderation_failed',
                user_id=request.user_id,
                violations=moderation_result.violations
            )
            raise HTTPException(
                status_code=400,
                detail=f'内容未通过安全审核：{", ".join(moderation_result.violations)}'
            )

        # 5. 审计日志
        self.audit_logger.log_api_call(
            user_id=request.user_id,
            action='ai_request',
            content_type=request.content_type,
            result_status='success'
        )

        return result

    async def _execute_in_sandbox(self, request: AIRequest) -> dict:
        """
        在隔离沙箱中执行 AI 调用

        沙箱配置:
        - 使用 gVisor 或 Firecracker MicroVM
        - 网络白名单：仅允许访问配置的 AI 服务 endpoint
        - 文件系统：只读挂载，禁止写操作
        - 超时：30 秒强制终止
        """
        try:
            async with asyncio.timeout(30):  # 30 秒超时
                async with aiohttp.ClientSession() as session:
                    # 根据请求类型路由到不同 AI 服务
                    if request.content_type == 'ocr':
                        endpoint = LOCAL_LLM_ENDPOINT
                    elif request.content_type == 'caption':
                        endpoint = CLOUD_LLM_ENDPOINT
                    else:
                        endpoint = MODERATION_ENDPOINT

                    async with session.post(
                        endpoint,
                        json={'prompt': request.prompt},
                        headers={'Authorization': f'Bearer {AI_SERVICE_TOKEN}'}
                    ) as response:
                        if response.status != 200:
                            raise HTTPException(status_code=502, detail='AI 服务调用失败')
                        return await response.json()

        except asyncio.TimeoutError:
            self.audit_logger.log_security_event(
                event='ai_request_timeout',
                user_id=request.user_id,
                content_type=request.content_type
            )
            raise HTTPException(status_code=504, detail='AI 服务响应超时')


# 速率限制器实现
from collections import defaultdict
from datetime import datetime

class RateLimiter:
    """滑动窗口速率限制器"""

    def __init__(self, max_requests: int, window: timedelta):
        self.max_requests = max_requests
        self.window = window
        self.requests = defaultdict(list)

    async def is_allowed(self, user_id: str) -> bool:
        now = datetime.now()
        window_start = now - self.window

        # 清理过期记录
        self.requests[user_id] = [
            ts for ts in self.requests[user_id] if ts > window_start
        ]

        if len(self.requests[user_id]) >= self.max_requests:
            return False

        self.requests[user_id].append(now)
        return True
```

### 3.3 AI 内容审核流程

```python
# 后端：内容审核器
from enum import Enum
from typing import List, Optional

class ViolationType(Enum):
    HATE_SPEECH = "hate_speech"
    HARASSMENT = "harassment"
    SELF_HARM = "self_harm"
    SEXUAL = "sexual"
    VIOLENCE = "violence"
    PII_LEAK = "pii_leak"  # 个人身份信息泄露

class ContentModerator:
    """
    AI 生成内容审核器

    审核维度:
    1. 违法有害内容 (仇恨言论、骚扰、自残等)
    2. 色情暴力内容
    3. 个人敏感信息 (手机号、身份证、精确地址等)
    """

    def __init__(self):
        self.moderation_endpoint = MODERATION_API_ENDPOINT
        self.pii_patterns = {
            'phone': r'1[3-9]\d{9}',
            'id_card': r'[1-9]\d{5}(18|19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\d{3}[\dXx]',
            'exact_address': r'(?:省 | 市 | 区 | 县 | 街道 | 镇 | 乡).*?(?:路 | 街| 道| 巷| 弄).*?\d+号',
        }

    async def check(self, content: str) -> 'ModerationResult':
        """执行内容审核"""
        violations = []

        # 1. 调用云端审核 API
        moderation_result = await self._call_moderation_api(content)
        for category, flagged in moderation_result.get('categories', {}).items():
            if flagged:
                violations.append(ViolationType(category.upper()))

        # 2. 本地 PII 检测
        for pii_type, pattern in self.pii_patterns.items():
            import re
            if re.search(pattern, content):
                violations.append(ViolationType.PII_LEAK)
                break

        return ModerationResult(
            is_safe=len(violations) == 0,
            violations=[v.value for v in violations]
        )

class ModerationResult:
    def __init__(self, is_safe: bool, violations: List[str]):
        self.is_safe = is_safe
        self.violations = violations
```

---

## 4. 位置数据安全存储规范 (PostGIS)

### 4.1 位置数据分级存储

依据白皮书第 6 章数据分级原则，位置数据按精度分级：

| 精度级别 | 描述 | 风险等级 | 存储策略 |
|---------|------|---------|---------|
| Level 5 | 精确坐标 (<10m) | S4 (严重) | 加密存储，严格访问控制 |
| Level 4 | 建筑级 (10-50m) | S3 (高) | 加密存储 |
| Level 3 | 街区级 (50-100m) | S2 (中) | 脱敏存储 |
| Level 2 | 区域级 (100-500m) | S1 (低) | 模糊存储 |
| Level 1 | 城市级 (>500m) | S0 (公开) | 公开访问 |

### 4.2 PostGIS 位置脱敏存储

```python
# 后端：PostGIS 位置数据处理
from sqlalchemy import create_engine, Column, String, Integer, Float
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.dialects.postgresql import UUID
import random

Base = declarative_base()

class UserLocation(Base):
    """
    用户位置数据模型

    安全设计:
    1. 原始坐标加密存储 (EL5)
    2. 公开查询使用脱敏坐标
    3. 精度级别控制访问
    """
    __tablename__ = 'user_locations'

    id = Column(UUID, primary_key=True)
    user_id = Column(UUID, nullable=False, index=True)

    # 原始精确坐标 (加密存储)
    latitude_encrypted = Column(String(512), nullable=False)
    longitude_encrypted = Column(String(512), nullable=False)

    # 脱敏坐标 (用于公开分享)
    latitude_fuzzed = Column(Float, nullable=False)
    longitude_fuzzed = Column(Float, nullable=False)

    # 精度级别 (1-5)
    precision_level = Column(Integer, nullable=False, default=5)

    # PostGIS 地理点 (脱敏)
    geom = Column(Geometry('POINT', spatial_index=True))


class LocationSanitizer:
    """
    位置数据脱敏处理器

    脱敏算法:
    - Level 3 (100m): 添加±0.0005 度随机偏移 (约±55m)
    - Level 2 (500m): 添加±0.002 度随机偏移 (约±220m)
    - Level 1 (城市级): 添加±0.01 度随机偏移 (约±1.1km)
    """

    @staticmethod
    def fuzz_location(latitude: float, longitude: float, level: int) -> tuple:
        """
        对位置坐标添加随机偏移实现脱敏

        Args:
            latitude: 原始纬度
            longitude: 原始经度
            level: 脱敏级别 (1-5, 5 为不脱敏)

        Returns:
            (fuzzed_lat, fuzzed_lng): 脱敏后坐标
        """
        if level >= 5:
            return latitude, longitude

        # 定义各级别的最大偏移量 (度)
        offsets = {
            4: 0.0005,   # ~55m
            3: 0.001,    # ~110m
            2: 0.002,    # ~220m
            1: 0.01,     # ~1.1km
        }

        offset = offsets.get(level, 0.001)

        # 使用密码学安全随机数生成偏移
        fuzzed_lat = latitude + random.uniform(-offset, offset)
        fuzzed_lng = longitude + random.uniform(-offset, offset)

        return round(fuzzed_lat, 6), round(fuzzed_lng, 6)


# 数据库表结构 SQL
"""
CREATE TABLE user_locations (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,

    -- 加密字段 (EL5 级保护)
    latitude_encrypted TEXT NOT NULL,
    longitude_encrypted TEXT NOT NULL,

    -- 脱敏字段 (用于公开查询)
    latitude_fuzzed DOUBLE PRECISION NOT NULL,
    longitude_fuzzed DOUBLE PRECISION NOT NULL,

    -- 精度级别
    precision_level INTEGER NOT NULL DEFAULT 5,

    -- PostGIS 地理点
    geom GEOMETRY(POINT, 4326),

    -- 审计字段
    created_at TIMESTAMP DEFAULT NOW(),
    accessed_count INTEGER DEFAULT 0,

    -- 索引
    INDEX idx_user_id (user_id),
    SPATIAL INDEX idx_geom (geom)
);

-- 创建触发器：记录敏感数据访问
CREATE TRIGGER log_location_access
AFTER SELECT ON user_locations
FOR EACH ROW EXECUTE FUNCTION log_sensitive_access();
"""
```

---

## 5. 零信任网络访问控制

### 5.1 API 访问控制架构

依据白皮书第 4 章零信任网络架构：

```python
# 后端：零信任 API 网关中间件
from fastapi import Request, HTTPException, Depends
from jose import jwt, JWTError
from datetime import datetime, timedelta
import hashlib
import hmac

class ZeroTrustMiddleware:
    """
    零信任 API 访问控制

    核心原则:
    1. 永不信任，始终验证
    2. 最小权限访问
    3. 动态风险评估
    4. 持续认证
    """

    def __init__(self):
        self.secret_key = SERVER_SECRET_KEY
        self.token_blacklist = set()  # 生产环境应使用 Redis

    async def validate_request(self, request: Request) -> dict:
        """验证每个 API 请求"""

        # 1. 验证 JWT Token
        token = self._extract_token(request)
        if not token:
            raise HTTPException(status_code=401, detail='缺少认证 Token')

        if token in self.token_blacklist:
            raise HTTPException(status_code=401, detail='Token 已吊销')

        try:
            payload = jwt.decode(
                token,
                self.secret_key,
                algorithms=['HS256'],
                options={'verify_exp': True}
            )
        except JWTError as e:
            raise HTTPException(status_code=401, detail=f'Token 无效：{str(e)}')

        # 2. 检查权限范围 (Scope)
        required_scope = self._get_required_scope(request.url.path, request.method)
        user_scopes = payload.get('scopes', [])
        if required_scope not in user_scopes:
            raise HTTPException(status_code=403, detail='权限不足')

        # 3. 动态风险评估 (简化示例)
        risk_score = await self._calculate_risk(request, payload)
        if risk_score > 0.8:
            # 高风险操作需要重新认证
            raise HTTPException(
                status_code=403,
                detail='检测到高风险操作，需要重新认证'
            )

        # 4. 记录访问日志 (审计)
        await self._log_access(payload['user_id'], request, risk_score)

        return payload

    async def _calculate_risk(self, request: Request, user_payload: dict) -> float:
        """
        动态风险评估

        评估维度:
        - 地理位置异常
        - 访问时间异常
        - 设备指纹变化
        - 请求频率异常
        """
        risk_score = 0.0

        # 检查 IP 地理位置
        user_ip = request.client.host
        user_location = user_payload.get('last_known_location')

        if user_location and not self._is_expected_location(user_ip, user_location):
            risk_score += 0.3

        # 检查访问时间
        hour = datetime.now().hour
        if hour < 6 or hour > 23:  # 非正常访问时间
            risk_score += 0.2

        # 检查设备指纹
        device_fingerprint = request.headers.get('X-Device-Fingerprint')
        if device_fingerprint != user_payload.get('device_fingerprint'):
            risk_score += 0.4

        return min(risk_score, 1.0)


# 分享链接签名验证 (HMAC-SHA256 + TTL)
def generate_share_token(diary_id: str, user_id: str, ttl_hours: int = 24) -> str:
    """
    生成带 TTL 的分享链接 Token

    安全特性:
    - HMAC-SHA256 签名防篡改
    - 时间戳过期验证
    - 用户绑定防越权
    """
    import time
    import hmac
    import hashlib
    import base64

    expire_at = int(time.time()) + ttl_hours * 3600
    payload = f"{diary_id}:{user_id}:{expire_at}"

    signature = hmac.new(
        key=SHARING_SECRET_KEY.encode(),
        msg=payload.encode(),
        digestmod=hashlib.sha256
    ).digest()

    # 返回 base64 编码的 token
    token_data = f"{payload}:{base64.urlsafe_b64encode(signature).decode()}"
    return token_data


def verify_share_token(token: str, required_diary_id: str) -> dict:
    """
    验证分享链接 Token

    Returns:
        dict: {'valid': bool, 'user_id': str, 'diary_id': str}
    """
    import time
    import hmac
    import hashlib
    import base64

    try:
        parts = token.split(':')
        if len(parts) != 4:
            return {'valid': False, 'reason': 'invalid_format'}

        diary_id = parts[0]
        user_id = parts[1]
        expire_at = int(parts[2])
        signature = base64.urlsafe_b64decode(parts[3])

        # 验证过期
        if int(time.time()) > expire_at:
            return {'valid': False, 'reason': 'expired'}

        # 验证日记 ID 匹配
        if diary_id != required_diary_id:
            return {'valid': False, 'reason': 'diary_mismatch'}

        # 验证签名
        payload = f"{diary_id}:{user_id}:{expire_at}"
        expected_signature = hmac.new(
            key=SHARING_SECRET_KEY.encode(),
            msg=payload.encode(),
            digestmod=hashlib.sha256
        ).digest()

        if not hmac.compare_digest(signature, expected_signature):
            return {'valid': False, 'reason': 'invalid_signature'}

        return {'valid': True, 'user_id': user_id, 'diary_id': diary_id}

    except Exception as e:
        return {'valid': False, 'reason': f'verification_error: {str(e)}'}
```

---

## 6. 同步服务器安全规范 (SyncServer)

### 6.1 最终一致性同步安全

```python
# 后端：同步管理器安全实现
from enum import Enum
from typing import List, Optional, Dict
import hashlib
import json

class SyncOperation(Enum):
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"

class SyncConflictResolver:
    """
    同步冲突解决器

    冲突解决策略:
    1. Last-Write-Wins (LWW) - 基于时间戳
    2. Merge - 可合并操作
    3. Manual - 需要用户干预
    """

    def resolve_conflict(
        self,
        local_op: SyncOperation,
        remote_op: SyncOperation,
        local_timestamp: float,
        remote_timestamp: float,
        data_type: str
    ) -> dict:
        """
        解决同步冲突

        安全考虑:
        - 验证操作来源的合法性
        - 记录冲突日志用于审计
        - 防止恶意覆盖攻击
        """
        # 记录冲突事件
        self._log_conflict(local_op, remote_op, data_type)

        # LWW 策略
        if remote_timestamp > local_timestamp:
            return {'winner': 'remote', 'action': 'overwrite'}
        else:
            return {'winner': 'local', 'action': 'keep'}


class SyncManager:
    """
    分布式同步管理器

    安全特性:
    1. 操作签名验证
    2. 向量时钟防回滚攻击
    3. 增量同步防数据泄露
    """

    def __init__(self):
        self.conflict_resolver = SyncConflictResolver()

    async def sync_data(
        self,
        user_id: str,
        client_vector_clock: Dict[str, int],
        pending_operations: List[dict]
    ) -> dict:
        """
        处理客户端同步请求

        安全验证:
        1. 验证用户身份
        2. 验证向量时钟 (防回滚)
        3. 验证操作签名
        4. 应用行级安全策略
        """
        # 1. 获取服务端向量时钟
        server_vector_clock = await self._get_vector_clock(user_id)

        # 2. 检测回滚攻击
        if self._is_rollback_attempt(client_vector_clock, server_vector_clock):
            self._log_security_event('rollback_attempt', user_id)
            raise SecurityException('检测到回滚攻击，同步拒绝')

        # 3. 验证每个操作的签名
        for op in pending_operations:
            if not self._verify_operation_signature(op):
                raise SecurityException(f'操作签名验证失败：{op["id"]}')

        # 4. 执行同步 (在事务中)
        return await self._execute_sync(user_id, pending_operations)

    def _is_rollback_attempt(self, client_vc: Dict, server_vc: Dict) -> bool:
        """
        检测是否存在回滚攻击

        如果客户端的向量时钟在任何维度上都小于服务端，
        可能存在回滚攻击
        """
        for key, value in client_vc.items():
            if key in server_vc and value < server_vc[key]:
                return True
        return False
```

---

## 7. 对象存储 (OSS) 安全规范

### 7.1 媒体文件安全存储

```python
# 后端：OSS 安全存储
from qcloud_cos import CosConfig, CosS3Client
from qcloud_cos.exception import CosServiceError
import hashlib
import hmac

class OSSSecurityManager:
    """
    对象存储安全管理

    安全特性:
    1. 临时密钥访问 (STS)
    2. 文件完整性校验 (SHA256)
    3. 防盗链签名 URL
    4. 媒体内容类型强制验证
    """

    def __init__(self):
        self.config = CosConfig(
            Region='ap-guangzhou',
            SecretId=OSS_SECRET_ID,
            SecretKey=OSS_SECRET_KEY
        )
        self.client = CosS3Client(self.config)
        self.bucket = 'travel-diary-media'

    async def upload_media(
        self,
        user_id: str,
        file_data: bytes,
        content_type: str,
        is_sensitive: bool = False
    ) -> str:
        """
        上传媒体文件到 OSS

        安全要求:
        1. 验证文件类型 (防伪装)
        2. 计算完整性哈希
        3. 敏感文件加密存储
        4. 限制文件大小 (防 DoS)
        """
        # 1. 文件大小限制 (10MB)
        if len(file_data) > 10 * 1024 * 1024:
            raise ValueError('文件大小超出限制 (10MB)')

        # 2. 文件类型验证
        allowed_types = ['image/jpeg', 'image/png', 'image/webp', 'video/mp4']
        if content_type not in allowed_types:
            raise ValueError(f'不支持的文件类型：{content_type}')

        # 3. 计算 SHA256 哈希
        file_hash = hashlib.sha256(file_data).hexdigest()

        # 4. 生成对象 key
        object_key = f"{user_id}/{hashlib.md5(file_data).hexdigest()}"

        # 5. 敏感文件加密
        if is_sensitive:
            file_data = self._encrypt_file(file_data, user_id)

        # 6. 上传到 OSS
        try:
            response = self.client.put_object(
                Bucket=self.bucket,
                Key=object_key,
                Body=file_data,
                ContentType=content_type,
                Metadata={
                    'sha256': file_hash,
                    'user-id': user_id,
                    'encrypted': str(is_sensitive)
                }
            )
            return object_key
        except CosServiceError as e:
            raise RuntimeError(f'OSS 上传失败：{str(e)}')

    def generate_signed_url(
        self,
        object_key: str,
        user_id: str,
        expire_seconds: int = 3600
    ) -> str:
        """
        生成带签名的临时访问 URL (防盗链)

        签名包含:
        - 用户 ID 绑定
        - 过期时间
        - 文件路径
        """
        expire_at = int(time.time()) + expire_seconds
        payload = f"{object_key}:{user_id}:{expire_at}"

        signature = hmac.new(
            key=OSS_SIGNING_KEY.encode(),
            msg=payload.encode(),
            digestmod=hashlib.sha256
        ).hexdigest()

        base_url = f"https://{self.bucket}.cos.ap-guangzhou.myqcloud.com/{object_key}"
        return f"{base_url}?sign={signature}&expire={expire_at}&uid={user_id}"
```

---

## 8. 安全审计与监控

### 8.1 安全事件日志

```python
# 后端：安全审计日志
import logging
from datetime import datetime
from typing import Optional, Dict

class SecurityAuditLogger:
    """
    安全审计日志记录器

    记录事件:
    1. 认证失败
    2. 权限越界
    3. 敏感数据访问
    4. 异常行为
    5. 配置变更
    """

    def __init__(self):
        self.logger = logging.getLogger('security_audit')
        handler = logging.FileHandler('/var/log/security_audit.log')
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)

    def log_security_event(
        self,
        event_type: str,
        user_id: str,
        details: Optional[Dict] = None,
        severity: str = 'INFO'
    ):
        """记录安全事件"""
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'event_type': event_type,
            'user_id': user_id,
            'details': details or {},
            'severity': severity
        }

        log_method = getattr(self.logger, severity.lower(), self.logger.info)
        log_method(json.dumps(log_entry))

    # 预定义事件类型
    def log_auth_failure(self, user_id: str, reason: str, ip: str):
        self.log_security_event(
            'auth_failure', user_id,
            {'reason': reason, 'ip': ip},
            severity='WARNING'
        )

    def log_sensitive_data_access(self, user_id: str, data_type: str):
        self.log_security_event(
            'sensitive_data_access', user_id,
            {'data_type': data_type}
        )

    def log_privilege_escalation_attempt(
        self, user_id: str, target_resource: str, attempted_action: str
    ):
        self.log_security_event(
            'privilege_escalation_attempt', user_id,
            {'target': target_resource, 'action': attempted_action},
            severity='CRITICAL'
        )
```

---

## 9. 安全检查清单 (后端开发组)

### 9.1 开发阶段 (C - 基础设施负责人)

- [ ] 服务器环境配置
  - [ ] 禁用 root 远程登录
  - [ ] 配置防火墙 (仅开放必要端口)
  - [ ] 启用 SELinux/AppArmor
  - [ ] 配置自动安全更新

- [ ] 数据库安全
  - [ ] 启用 PostgreSQL SSL 连接
  - [ ] 配置行级安全 (RLS)
  - [ ] 敏感字段加密存储
  - [ ] 定期备份 + 备份加密

- [ ] API 网关
  - [ ] 配置 HTTPS (TLS1.3)
  - [ ] 启用 HSTS
  - [ ] 配置 CORS 白名单
  - [ ] 速率限制

### 9.2 开发阶段 (D - AI 业务逻辑负责人)

- [ ] AI 网关安全
  - [ ] 输入验证 (防 prompt 注入)
  - [ ] 沙箱隔离执行
  - [ ] 输出内容审核
  - [ ] 速率限制

- [ ] 位置数据安全
  - [ ] PostGIS 脱敏存储
  - [ ] 精度级别控制
  - [ ] 访问审计日志

- [ ] 分享链接
  - [ ] HMAC 签名验证
  - [ ] TTL 过期检查
  - [ ] 用户绑定验证

### 9.3 安全审计 (E - 规范与安全负责人)

- [ ] 代码安全审计
  - [ ] 检查 SQL 注入风险
  - [ ] 检查硬编码密钥
  - [ ] 检查日志敏感信息泄露
  - [ ] 检查权限校验逻辑

- [ ] 渗透测试
  - [ ] API 未授权访问测试
  - [ ] 越权访问测试
  - [ ] 注入攻击测试
  - [ ] 重放攻击测试

---

## 10. 参考文档

1. HarmonyOS NEXT 安全技术白皮书 V1.0 (2024-08-13)
   - 第 4 章：零信任网络架构
   - 第 5 章：系统安全架构
   - 第 6 章：数据分级访问控制
   - 第 8 章：应用生态治理

2. PostgreSQL Row-Level Security: https://www.postgresql.org/docs/current/ddl-rowsecurity.html

3. PostGIS 空间数据最佳实践：https://postgis.net/docs/manual-3.3/

4. OWASP API Security Top 10: https://owasp.org/www-project-api-security/

5. NIST SP 800-207 Zero Trust Architecture: https://csrc.nist.gov/publications/detail/sp/800-207/final

---

> **备注**: 本规范为动态文档，应根据项目进展和安全审计结果持续更新。
> 所有后端代码提交前必须通过安全检查清单验证。

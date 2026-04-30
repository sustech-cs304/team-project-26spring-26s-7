/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Common Layer 统一导出入口

// Utils 导出
export { AppColors, AppDimens, AppTheme, RouterUrls, TravelSpecialValues, DEFAULT_MAP_LATITUDE, DEFAULT_MAP_LONGITUDE } from './utils/Constants';
export type { ThemePalette } from './utils/Constants';
export { logger } from './utils/Logger';
export { PhotoPickerUtil } from './utils/PhotoPickerUtil';
export {
  getDefaultMapCenter,
  getStoredPreferredMapCenter,
  hasStoredPreferredMapCenter,
  isValidMapCenter,
  requestCurrentLocation,
  resolveMapCenterFromNodes,
  savePreferredMapCenter,
  setMapCurrentLocationError,
  setMapCurrentLocationPending
} from './utils/MapLocationPreference';
export type { MapCenter, MapPreferenceSource, MapPreferenceState } from './utils/MapLocationPreference';

// Auth 导出
export { AuthService, CloudStorageService } from './auth';
export { CloudSyncService } from './sync/CloudSyncService';
export { SyncManager } from './sync/SyncManager';
export type { AuthUser } from './auth';

// Data Layer 导出
export { RdbHelper, SensitivityLevel } from './data/index';
export { TravelRepository } from './data/index';
export { MemoryNodeRepository } from './data/index';
export { PhotoMetadataRepository } from './data/index';

// Service Layer 类型导出
export type {
  MemoryNode,
  Trip,
  SyncStatus,
  CopywritingRequest,
  ShareInfo,
  RouteGenerator
} from './service/types';

// Service Layer 类导出
export {
  MapNodeInfo,
  TripSummary,
  TimelineNodeInfo,
  ToneOption,
  SharePlatform,
  RouterParam,
  ReplayNode,
  ReplayRoute,
  Position
} from './service/types';

// Service Layer 服务导出
export { IDataService } from './service/IDataService';
export { MockDataService } from './service/MockDataService';
export { DataServiceStub } from './service/DataServiceStub';
export { RdbDataService } from './service/RdbDataService';
export { CreateTravelInput, UpdateTravelInput, CreateNodeInput, UpdateNodeInput } from './service/IDataService';

// 配置导出
export { getDataService } from './ServiceConfig';

// API Layer 导出
export { HttpClient, HttpResponse } from './api/index';
export { AiGatewayClient, ImageCopyRequest } from './api/index';
export { AiEndpoints, ShareEndpoints, HttpTimeout, API_BASE_URL, API_VERSION } from './api/index';
export { MultipartFormData, VisionLLMClient, VisionLLMRequest, VisionLLMResponse } from './api/index';

// AI Layer 导出
export { LocalImageTagger } from './ai/index';
export { MetadataAggregator } from './ai/index';
export {
  PhotoMetadata,
  JourneyMetadata,
  AiCopyRequest,
  AiCopyResponse,
  AiCopyResponseData,
  VisualKitResult
} from './ai/index';

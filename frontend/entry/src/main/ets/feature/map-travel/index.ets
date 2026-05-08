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

// Feature: Map Travel 统一导出入口

// Views 导出
export { MapHomeView } from './views/MapHomeView';
export { TripListView } from './views/TripListView';
export { TripAlbumView } from './views/TripAlbumView';
export { NodeListView } from './views/NodeListView';

// Components 导出
export { PhotoSelector } from './components/PhotoSelector';
export { ReplayPhotoCard } from './components/ReplayPhotoCard';
export { ReplayProgressBar } from './components/ReplayProgressBar';
export { PhotoCardOverlay } from './components/PhotoCardOverlay';
export { ReplaySettingsSheet } from './components/ReplaySettingsSheet';

// Pages 导出（如需在 feature 间引用）
export { NodeEditPage } from './pages/NodeEditPage';
export { NodeDetailPage } from './pages/NodeDetailPage';
export { TripEditPage } from './pages/TripEditPage';
export { TripDetailPage } from './pages/TripDetailPage';
export { TripReplayPage } from './pages/TripReplayPage';
export { LocationPickerPage } from './pages/LocationPickerPage';

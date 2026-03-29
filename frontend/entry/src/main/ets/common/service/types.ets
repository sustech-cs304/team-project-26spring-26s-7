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

/**
 * 核心数据模型定义
 * Service Layer 统一类型定义
 */

/** 地图上的记忆节点 Pin */
export class MapNodeInfo {
  id: string = ''
  title: string = ''
  poiName: string = ''
  latitude: number = 0
  longitude: number = 0

  constructor(id: string, title: string, poiName: string, latitude: number, longitude: number) {
    this.id = id
    this.title = title
    this.poiName = poiName
    this.latitude = latitude
    this.longitude = longitude
  }
}

/** 旅行卡片摘要 */
export class TripSummary {
  id: string = ''
  name: string = ''
  dateRange: string = ''
  nodeCount: string = '0'
  distance: string = '0'

  constructor(id: string, name: string, dateRange: string, nodeCount: string, distance: string) {
    this.id = id
    this.name = name
    this.dateRange = dateRange
    this.nodeCount = nodeCount
    this.distance = distance
  }
}

/** 时间轴节点摘要 */
export class TimelineNodeInfo {
  id: string = ''
  date: string = ''
  place: string = ''
  summary: string = ''
  photoCount: string = '0'

  constructor(id: string, date: string, place: string, summary: string, photoCount: string) {
    this.id = id
    this.date = date
    this.place = place
    this.summary = summary
    this.photoCount = photoCount
  }
}

/** AI 文案风格选项 */
export class ToneOption {
  key: string = ''
  label: string = ''

  constructor(key: string, label: string) {
    this.key = key
    this.label = label
  }
}

/** 分享平台选项 */
export class SharePlatform {
  icon: string = ''
  name: string = ''

  constructor(icon: string, name: string) {
    this.icon = icon
    this.name = name
  }
}

/** 路由参数 */
export class RouterParam {
  nodeId: string = ''
  tripId: string = ''
  latitude: number = 0
  longitude: number = 0
}

/** 记忆节点 - 完整数据模型 */
export interface MemoryNode {
  id: string
  title: string
  content: string
  latitude: number
  longitude: number
  poiName: string
  photos: string[]
  mood: string
  tags: string[]
  tripId?: string
  createdAt: number
  updatedAt: number
}

/** 旅行路线 - 完整数据模型 */
export interface Trip {
  id: string
  name: string
  coverPhoto?: string
  startDate: number
  endDate: number
  nodeIds: string[]
  totalDistance: number
  createdAt: number
  updatedAt: number
}

/** 同步状态 */
export interface SyncStatus {
  lastSyncTime: number
  pendingCount: number
  isSyncing: boolean
}

/** AI 文案请求 */
export interface CopywritingRequest {
  tripId: string
  poiNames: string[]
  totalDistance: number
  duration: number
  userDraft?: string
  tone: string
}

/** 分享信息 */
export interface ShareInfo {
  url: string
  copyText: string
  expireDays: number
}

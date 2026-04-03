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

import { MockDataService } from './service/MockDataService';
import { DataServiceStub } from './service/DataServiceStub';
import { RdbDataService } from './service/RdbDataService';
import type { IDataService } from './service/IDataService';

/**
 * 数据服务配置开关
 *
 * 三种模式：
 * - USE_MOCK_DATA = true: MockDataService，显示模拟数据（Previewer 默认）
 * - USE_RDB = true: RdbDataService，使用真实 RDB 数据库
 * - 都为 false: DataServiceStub，返回空数据
 */

/**
 * 是否使用 Mock 数据（显示演示数据）
 * 当前关闭，优先走真实 RDB
 */
const USE_MOCK_DATA = false;

/**
 * 是否使用 RDB 数据库
 * 当前开启，前端页面默认接入真实数据库
 */
const USE_RDB = true;

let _serviceInstance: IDataService | null = null;

/**
 * 获取数据服务实例（单例）
 *
 * 优先级：USE_MOCK_DATA > USE_RDB > DataServiceStub
 */
export function getDataService(): IDataService {
  if (_serviceInstance !== null) {
    return _serviceInstance;
  }
  if (USE_MOCK_DATA) {
    _serviceInstance = new MockDataService();
  } else if (USE_RDB) {
    _serviceInstance = new RdbDataService();
  } else {
    _serviceInstance = new DataServiceStub();
  }
  return _serviceInstance;
}

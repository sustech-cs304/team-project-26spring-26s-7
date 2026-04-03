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
import type { IDataService } from './service/IDataService';

/**
 * 数据服务配置开关
 *
 * 使用说明：
 * - USE_MOCK_DATA = true: 使用 MockDataService，显示模拟数据（默认）
 * - USE_MOCK_DATA = false: 使用 DataServiceStub，返回空数据（数据库占位）
 *
 * 队友完成数据库代码后：
 * 1. 将真实 DataService 实现后导入
 * 2. 修改为 useDatabase() 函数返回真实服务
 */

/**
 * 是否使用 Mock 数据（显示演示数据）
 * 默认 true，确保 Previewer 能正常显示
 */
const USE_MOCK_DATA = true;

/**
 * MockDataService 单例，确保内存数据跨页面共享
 */
let mockInstance: MockDataService | null = null;

/**
 * 获取数据服务实例（单例）
 *
 * 切换说明：
 * - 当前：USE_MOCK_DATA = true → MockDataService（显示模拟数据）
 * - 数据库占位：USE_MOCK_DATA = false → DataServiceStub（空数据）
 * - 数据库完成：导入真实 DataService 并切换
 */
export function getDataService(): IDataService {
  if (USE_MOCK_DATA) {
    if (!mockInstance) {
      mockInstance = new MockDataService();
    }
    return mockInstance;
  } else {
    return new DataServiceStub();
  }
}

/**
 * 获取数据服务实例（真实数据库版本）
 * 队友完成数据库代码后，启用此函数
 */
// export function getDatabaseService(): IDataService {
//   // TODO: 队友完成后取消注释并实现
//   // return new DataService();
//   return new MockDataService(); // 临时返回 Mock
// }

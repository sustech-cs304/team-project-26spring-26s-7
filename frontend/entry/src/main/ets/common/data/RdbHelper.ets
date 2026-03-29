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

import { logger } from '../utils/Logger';

const TAG = 'RdbHelper';

/**
 * RDB 数据库助手
 *
 * 功能职责：
 * - 管理关系型数据库（RDB）连接
 * - 提供表创建、升级迁移
 * - 封装 CRUD 基础操作
 *
 * 数据库 Schema：
 * - travels 表：id, name, cover_image_uri, start_date, end_date, created_at
 * - memory_nodes 表：id, travel_id, latitude, longitude, photo_uri, description, address, created_at
 *
 * 依赖：
 * - @kit.ArkData (relationalStore 模块)
 *
 * ---
 * 实现负责人：[队友姓名]
 * 参考文档：references/F1_local_storage_assignment.md
 * ---
 *
 * TODO: 需要实现：
 * 1. 导入 @kit.ArkData.relationalStore
 * 2. 实现 initDatabase() 创建/打开数据库
 * 3. 实现 createTables() 初始化表结构
 * 4. 实现增删改查基础方法
 * 5. 数据分级标识（S0-S4）的存储和管理
 * 6. 数据库版本管理（onUpgrade）
 */

/**
 * 数据分级枚举（华为鸿蒙安全合规要求）
 * 参考：references/F1_local_storage_assignment.md 一、1.2
 */
export enum SensitivityLevel {
  S0 = 'S0',  // 公开数据
  S1 = 'S1',  // 一般数据（旅行名称、标签）
  S2 = 'S2',  // 敏感数据（经纬度、时间戳、地址）
  S3 = 'S3',  // 个人敏感信息（用户草稿、心情标记）
  S4 = 'S4'   // 高度敏感（本应用不涉及）
}

/**
 * 数据库配置常量
 */
const DB_NAME = 'TravelPin.db';
const DB_VERSION = 1;

export class RdbHelper {
  private static instance: RdbHelper;
  private rdb: object | null = null; // TODO: relationalStore.RdbStore 类型
  private readonly dbName: string = DB_NAME;

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): RdbHelper {
    if (!RdbHelper.instance) {
      RdbHelper.instance = new RdbHelper();
    }
    return RdbHelper.instance;
  }

  /**
   * 初始化数据库
   *
   * TODO: 实现步骤：
   * 1. 配置 StoreConfig
   * 2. 调用 relationalStore.getRdbStore()
   * 3. 获取 rdb 实例
   * 4. 调用 createTables() 创建表
   */
  async initDatabase(): Promise<void> {
    logger.info(TAG, 'Initializing database (STUB - to be implemented)');
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 Promise.resolve()
    // 队友完成后请替换为真实实现
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve();
  }

  /**
   * 创建表结构
   *
   * TODO: 实现步骤：
   * 1. CREATE TABLE IF NOT EXISTS travels (...)
   * 2. CREATE TABLE IF NOT EXISTS memory_nodes (...)
   * 3. 添加数据分级标识字段 sensitivity
   */
  async createTables(): Promise<void> {
    logger.info(TAG, 'Creating tables (STUB - to be implemented)');
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve();
  }

  /**
   * 执行 SQL 查询
   * @param sql SQL 语句
   * @param params 参数数组
   */
  async query(sql: string, params?: string[]): Promise<string[]> {
    logger.debug(TAG, `Executing query: ${sql} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回空数组
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve([]);
  }

  /**
   * 执行 SQL 更新
   * @param sql SQL 语句
   * @param params 参数数组
   */
  async execute(sql: string, params?: string[]): Promise<void> {
    logger.debug(TAG, `Executing update: ${sql} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve();
  }

  /**
   * 关闭数据库连接
   */
  async close(): Promise<void> {
    if (this.rdb) {
      logger.info(TAG, 'Closing database');
      // TODO: await this.rdb.close();
      this.rdb = null;
    }
  }
}

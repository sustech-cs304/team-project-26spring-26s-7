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

import { relationalStore as rdb } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from '../utils/Logger';

const TAG = 'RdbHelper';

/**
 * 数据分级枚举（华为鸿蒙安全合规要求）
 */
export enum SensitivityLevel {
  S0 = 'S0',
  S1 = 'S1',
  S2 = 'S2',
  S3 = 'S3',
  S4 = 'S4'
}

const DB_NAME = 'TravelPin.db';
const DB_VERSION = 1;

const STORE_CONFIG: rdb.StoreConfig = {
  name: DB_NAME,
  securityLevel: rdb.SecurityLevel.S2
};

const SQL_CREATE_TRAVELS = `
  CREATE TABLE IF NOT EXISTS travels(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    cover_image_uri TEXT,
    start_date INTEGER NOT NULL,
    end_date INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sensitivity TEXT NOT NULL DEFAULT 'S1'
  )
`;

const SQL_CREATE_MEMORY_NODES = `
  CREATE TABLE IF NOT EXISTS memory_nodes(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    travel_id INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    title TEXT,
    poi_name TEXT,
    description TEXT,
    address TEXT,
    mood TEXT,
    tags TEXT,
    photos TEXT,
    node_order INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sensitivity TEXT NOT NULL DEFAULT 'S2',
    FOREIGN KEY (travel_id) REFERENCES travels(id) ON DELETE CASCADE
  )
`;

const SQL_ADD_MEMORY_NODE_TITLE = `
  ALTER TABLE memory_nodes ADD COLUMN title TEXT
`;

const SQL_ADD_MEMORY_NODE_POI_NAME = `
  ALTER TABLE memory_nodes ADD COLUMN poi_name TEXT
`;

const SQL_ADD_MEMORY_NODE_DESCRIPTION = `
  ALTER TABLE memory_nodes ADD COLUMN description TEXT
`;

const SQL_ADD_MEMORY_NODE_ADDRESS = `
  ALTER TABLE memory_nodes ADD COLUMN address TEXT
`;

const SQL_ADD_MEMORY_NODE_MOOD = `
  ALTER TABLE memory_nodes ADD COLUMN mood TEXT
`;

const SQL_ADD_MEMORY_NODE_TAGS = `
  ALTER TABLE memory_nodes ADD COLUMN tags TEXT
`;

const SQL_ADD_MEMORY_NODE_PHOTOS = `
  ALTER TABLE memory_nodes ADD COLUMN photos TEXT
`;

const SQL_ADD_MEMORY_NODE_ORDER = `
  ALTER TABLE memory_nodes ADD COLUMN node_order INTEGER DEFAULT 0
`;

const SQL_ADD_MEMORY_NODE_SENSITIVITY = `
  ALTER TABLE memory_nodes ADD COLUMN sensitivity TEXT NOT NULL DEFAULT 'S2'
`;

const SQL_MIGRATE_MEMORY_NODE_ORDER = `
  UPDATE memory_nodes SET node_order = "order" WHERE node_order = 0
`;

const SQL_CREATE_SYNC_QUEUE = `
  CREATE TABLE IF NOT EXISTS sync_queue(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL,
    entity_id INTEGER NOT NULL,
    operation TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    retry_count INTEGER DEFAULT 0
  )
`;

export class RdbHelper {
  private static instance: RdbHelper;
  private rdbStore: rdb.RdbStore | undefined = undefined;
  private initialized: boolean = false;
  private appContext: common.Context | undefined = undefined;
  private initPromise: Promise<void> | null = null;

  private constructor() {}

  private toError(err: Object): Error {
    return new Error(JSON.stringify(err));
  }

  static getInstance(): RdbHelper {
    if (!RdbHelper.instance) {
      RdbHelper.instance = new RdbHelper();
    }
    return RdbHelper.instance;
  }

  /**
   * 初始化数据库（需要在 EntryAbility 中调用）
   */
  async initDatabase(context: common.Context): Promise<void> {
    this.appContext = context;
    if (this.initialized && this.rdbStore) {
      logger.info(TAG, 'Database already initialized');
      return;
    }
    if (this.initPromise) {
      await this.initPromise;
      return;
    }

    this.initPromise = (async () => {
      try {
        logger.info(TAG, `Initializing database v${DB_VERSION}...`);
        this.rdbStore = await rdb.getRdbStore(context, STORE_CONFIG);
        await this.createTables();
        this.initialized = true;
        logger.info(TAG, 'Database initialized successfully');
      } catch (err) {
        logger.error(TAG, `Database initialization failed: ${JSON.stringify(err)}`);
        throw this.toError(err);
      }
    })();

    try {
      await this.initPromise;
    } finally {
      this.initPromise = null;
    }
  }

  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore not initialized');
    }
    await this.rdbStore.executeSql(SQL_CREATE_TRAVELS);
    await this.rdbStore.executeSql(SQL_CREATE_MEMORY_NODES);
    await this.rdbStore.executeSql(SQL_CREATE_SYNC_QUEUE);
    await this.ensureLatestSchema();
    logger.info(TAG, 'Tables created successfully');
  }

  private async ensureLatestSchema(): Promise<void> {
    const optionalSchemaUpdates: string[] = [
      SQL_ADD_MEMORY_NODE_TITLE,
      SQL_ADD_MEMORY_NODE_POI_NAME,
      SQL_ADD_MEMORY_NODE_DESCRIPTION,
      SQL_ADD_MEMORY_NODE_ADDRESS,
      SQL_ADD_MEMORY_NODE_MOOD,
      SQL_ADD_MEMORY_NODE_TAGS,
      SQL_ADD_MEMORY_NODE_PHOTOS,
      SQL_ADD_MEMORY_NODE_ORDER,
      SQL_ADD_MEMORY_NODE_SENSITIVITY
    ];

    for (let i = 0; i < optionalSchemaUpdates.length; i++) {
      await this.safeExecuteSql(optionalSchemaUpdates[i]);
    }

    await this.safeExecuteSql(SQL_MIGRATE_MEMORY_NODE_ORDER);
  }

  private async safeExecuteSql(sql: string): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(sql);
    } catch (err) {
      logger.info(TAG, `Skipping optional SQL execution: ${JSON.stringify(err)}`);
    }
  }

  getRdbStore(): rdb.RdbStore | undefined {
    return this.rdbStore;
  }

  async getStore(): Promise<rdb.RdbStore> {
    if (this.initialized && this.rdbStore) {
      return this.rdbStore;
    }
    if (this.initPromise) {
      await this.initPromise;
    } else if (this.appContext) {
      await this.initDatabase(this.appContext);
    }

    if (!this.rdbStore) {
      throw new Error('RdbStore not initialized. Call RdbHelper.initDatabase() first.');
    }
    return this.rdbStore;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async close(): Promise<void> {
    if (this.rdbStore) {
      logger.info(TAG, 'Closing database');
      this.rdbStore = undefined;
      this.initialized = false;
    }
  }
}

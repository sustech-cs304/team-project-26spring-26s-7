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
import type { SyncQueueItem } from '../service/types';

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
    sensitivity TEXT NOT NULL DEFAULT 'S1',
    owner_uid TEXT NOT NULL DEFAULT '',
    cloud_id TEXT DEFAULT '',
    sync_status TEXT NOT NULL DEFAULT 'local_only',
    deleted_at INTEGER DEFAULT 0,
    last_synced_at INTEGER DEFAULT 0,
    version INTEGER NOT NULL DEFAULT 1
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
    photo_manifest TEXT DEFAULT '',
    node_order INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sensitivity TEXT NOT NULL DEFAULT 'S2',
    owner_uid TEXT NOT NULL DEFAULT '',
    cloud_id TEXT DEFAULT '',
    sync_status TEXT NOT NULL DEFAULT 'local_only',
    deleted_at INTEGER DEFAULT 0,
    last_synced_at INTEGER DEFAULT 0,
    version INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (travel_id) REFERENCES travels(id) ON DELETE CASCADE
  )
`;

const SQL_ADD_TRAVEL_OWNER_UID = `
  ALTER TABLE travels ADD COLUMN owner_uid TEXT NOT NULL DEFAULT ''
`;

const SQL_ADD_TRAVEL_CLOUD_ID = `
  ALTER TABLE travels ADD COLUMN cloud_id TEXT DEFAULT ''
`;

const SQL_ADD_TRAVEL_SYNC_STATUS = `
  ALTER TABLE travels ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'local_only'
`;

const SQL_ADD_TRAVEL_DELETED_AT = `
  ALTER TABLE travels ADD COLUMN deleted_at INTEGER DEFAULT 0
`;

const SQL_ADD_TRAVEL_LAST_SYNCED_AT = `
  ALTER TABLE travels ADD COLUMN last_synced_at INTEGER DEFAULT 0
`;

const SQL_ADD_TRAVEL_VERSION = `
  ALTER TABLE travels ADD COLUMN version INTEGER NOT NULL DEFAULT 1
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

const SQL_ADD_MEMORY_NODE_PHOTO_MANIFEST = `
  ALTER TABLE memory_nodes ADD COLUMN photo_manifest TEXT DEFAULT ''
`;

const SQL_ADD_MEMORY_NODE_ORDER = `
  ALTER TABLE memory_nodes ADD COLUMN node_order INTEGER DEFAULT 0
`;

const SQL_ADD_MEMORY_NODE_SENSITIVITY = `
  ALTER TABLE memory_nodes ADD COLUMN sensitivity TEXT NOT NULL DEFAULT 'S2'
`;

const SQL_ADD_MEMORY_NODE_OWNER_UID = `
  ALTER TABLE memory_nodes ADD COLUMN owner_uid TEXT NOT NULL DEFAULT ''
`;

const SQL_ADD_MEMORY_NODE_CLOUD_ID = `
  ALTER TABLE memory_nodes ADD COLUMN cloud_id TEXT DEFAULT ''
`;

const SQL_ADD_MEMORY_NODE_SYNC_STATUS = `
  ALTER TABLE memory_nodes ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'local_only'
`;

const SQL_ADD_MEMORY_NODE_DELETED_AT = `
  ALTER TABLE memory_nodes ADD COLUMN deleted_at INTEGER DEFAULT 0
`;

const SQL_ADD_MEMORY_NODE_LAST_SYNCED_AT = `
  ALTER TABLE memory_nodes ADD COLUMN last_synced_at INTEGER DEFAULT 0
`;

const SQL_ADD_MEMORY_NODE_VERSION = `
  ALTER TABLE memory_nodes ADD COLUMN version INTEGER NOT NULL DEFAULT 1
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
      SQL_ADD_TRAVEL_OWNER_UID,
      SQL_ADD_TRAVEL_CLOUD_ID,
      SQL_ADD_TRAVEL_SYNC_STATUS,
      SQL_ADD_TRAVEL_DELETED_AT,
      SQL_ADD_TRAVEL_LAST_SYNCED_AT,
      SQL_ADD_TRAVEL_VERSION,
      SQL_ADD_MEMORY_NODE_TITLE,
      SQL_ADD_MEMORY_NODE_POI_NAME,
      SQL_ADD_MEMORY_NODE_DESCRIPTION,
      SQL_ADD_MEMORY_NODE_ADDRESS,
      SQL_ADD_MEMORY_NODE_MOOD,
      SQL_ADD_MEMORY_NODE_TAGS,
      SQL_ADD_MEMORY_NODE_PHOTOS,
      SQL_ADD_MEMORY_NODE_PHOTO_MANIFEST,
      SQL_ADD_MEMORY_NODE_ORDER,
      SQL_ADD_MEMORY_NODE_SENSITIVITY,
      SQL_ADD_MEMORY_NODE_OWNER_UID,
      SQL_ADD_MEMORY_NODE_CLOUD_ID,
      SQL_ADD_MEMORY_NODE_SYNC_STATUS,
      SQL_ADD_MEMORY_NODE_DELETED_AT,
      SQL_ADD_MEMORY_NODE_LAST_SYNCED_AT,
      SQL_ADD_MEMORY_NODE_VERSION
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

  async getPendingSyncQueueItems(): Promise<SyncQueueItem[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getStore();
      const predicates = new rdb.RdbPredicates('sync_queue');
      predicates.orderByAsc('created_at');
      resultSet = await store.query(predicates);
      const items: SyncQueueItem[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          items.push({
            id: resultSet.getDouble(resultSet.getColumnIndex('id')).toString(),
            entityType: resultSet.getString(resultSet.getColumnIndex('entity_type')),
            entityId: resultSet.getDouble(resultSet.getColumnIndex('entity_id')).toString(),
            operation: resultSet.getString(resultSet.getColumnIndex('operation')),
            payload: resultSet.getString(resultSet.getColumnIndex('payload')),
            createdAt: resultSet.getDouble(resultSet.getColumnIndex('created_at')),
            retryCount: resultSet.getDouble(resultSet.getColumnIndex('retry_count'))
          });
        } while (resultSet.goToNextRow());
      }
      return items;
    } catch (err) {
      logger.error(TAG, `getPendingSyncQueueItems failed: ${JSON.stringify(err)}`);
      return [];
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (_) {}
      }
    }
  }

  async getLatestSyncTimestamp(): Promise<number> {
    const items = await this.getPendingSyncQueueItems();
    if (items.length === 0) {
      return Date.now();
    }
    return items[items.length - 1].createdAt;
  }

  async enqueueSyncItem(entityType: string, entityId: string, operation: string, payload: string): Promise<void> {
    const store = await this.getStore();
    await store.insert('sync_queue', {
      entity_type: entityType,
      entity_id: Number(entityId),
      operation: operation,
      payload: payload,
      created_at: Date.now(),
      retry_count: 0
    });
  }

  async removeSyncItems(entityType: string, entityId: string): Promise<void> {
    const store = await this.getStore();
    const predicates = new rdb.RdbPredicates('sync_queue');
    predicates.equalTo('entity_type', entityType);
    predicates.equalTo('entity_id', Number(entityId));
    await store.delete(predicates);
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

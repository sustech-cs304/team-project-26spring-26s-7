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

/** 用户 profile 数据结构，对应 user_profile 表 */
export interface UserProfileRow {
  ownerUid: string;
  displayName: string;
  avatarPath: string;
  bio: string;
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
    is_public INTEGER NOT NULL DEFAULT 0,
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
    version INTEGER NOT NULL DEFAULT 1,
    replay_style_kit_id TEXT DEFAULT '',
    replay_bgm_id TEXT DEFAULT '',
    replay_filter_id TEXT DEFAULT '',
    replay_transition_type TEXT DEFAULT '',
    replay_enable_ripple INTEGER DEFAULT 0,
    replay_enable_route_animation INTEGER DEFAULT 0,
    replay_enable_blur_overlay INTEGER DEFAULT 0
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

const SQL_ADD_TRAVEL_REPLAY_STYLE_KIT_ID = `
  ALTER TABLE travels ADD COLUMN replay_style_kit_id TEXT DEFAULT ''
`;

const SQL_ADD_TRAVEL_REPLAY_BGM_ID = `
  ALTER TABLE travels ADD COLUMN replay_bgm_id TEXT DEFAULT ''
`;

const SQL_ADD_TRAVEL_REPLAY_FILTER_ID = `
  ALTER TABLE travels ADD COLUMN replay_filter_id TEXT DEFAULT ''
`;

const SQL_ADD_TRAVEL_REPLAY_TRANSITION_TYPE = `
  ALTER TABLE travels ADD COLUMN replay_transition_type TEXT DEFAULT ''
`;

const SQL_ADD_TRAVEL_REPLAY_ENABLE_RIPPLE = `
  ALTER TABLE travels ADD COLUMN replay_enable_ripple INTEGER DEFAULT 0
`;

const SQL_ADD_TRAVEL_REPLAY_ENABLE_ROUTE_ANIMATION = `
  ALTER TABLE travels ADD COLUMN replay_enable_route_animation INTEGER DEFAULT 0
`;

const SQL_ADD_TRAVEL_REPLAY_ENABLE_BLUR_OVERLAY = `
  ALTER TABLE travels ADD COLUMN replay_enable_blur_overlay INTEGER DEFAULT 0
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

const SQL_ADD_TRAVEL_IS_PUBLIC = `
  ALTER TABLE travels ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0
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

const SQL_ADD_MEMORY_NODE_VISITED_AT = `
  ALTER TABLE memory_nodes ADD COLUMN visited_at INTEGER DEFAULT 0
`;

const SQL_MIGRATE_MEMORY_NODE_ORDER = `
  UPDATE memory_nodes SET node_order = "order" WHERE node_order = 0
`;

const SQL_CREATE_SYNC_QUEUE = `
  CREATE TABLE IF NOT EXISTS sync_queue(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_uid TEXT NOT NULL DEFAULT '',
    entity_type TEXT NOT NULL,
    entity_id INTEGER NOT NULL,
    operation TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    retry_count INTEGER DEFAULT 0
  )
`;

const SQL_CREATE_APP_SYNC_STATE = `
  CREATE TABLE IF NOT EXISTS app_sync_state(
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
`;

const SQL_CREATE_USER_PROFILE = `
  CREATE TABLE IF NOT EXISTS user_profile(
    id INTEGER PRIMARY KEY,
    owner_uid TEXT NOT NULL DEFAULT '',
    display_name TEXT DEFAULT '',
    avatar_path TEXT DEFAULT '',
    bio TEXT DEFAULT ''
  )
`;

const SQL_ADD_USER_PROFILE_OWNER_UID = `
  ALTER TABLE user_profile ADD COLUMN owner_uid TEXT NOT NULL DEFAULT ''
`;

const SQL_ADD_SYNC_QUEUE_OWNER_UID = `
  ALTER TABLE sync_queue ADD COLUMN owner_uid TEXT NOT NULL DEFAULT ''
`;

export class RdbHelper {
  private static instance: RdbHelper;
  static predicatesFactory: ((table: string) => Object) | null = null;
  static nowProvider: (() => number) | null = null;
  private rdbStore: rdb.RdbStore | undefined = undefined;
  private initialized: boolean = false;
  private appContext: common.Context | undefined = undefined;
  private initPromise: Promise<void> | null = null;

  private constructor() {}

  private toError(err: Object): Error {
    return new Error(JSON.stringify(err));
  }

  private static createPredicates(table: string): rdb.RdbPredicates {
    if (RdbHelper.predicatesFactory) {
      return RdbHelper.predicatesFactory(table) as rdb.RdbPredicates;
    }
    return new rdb.RdbPredicates(table);
  }

  private static now(): number {
    if (RdbHelper.nowProvider) {
      return RdbHelper.nowProvider();
    }
    return Date.now();
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

    // 创建初始化 promise 并等待其完全完成（包括所有内部 await）
    this.initPromise = this.initDatabaseInner(context);
    await this.initPromise;
    this.initPromise = null;
  }

  private async initDatabaseInner(context: common.Context): Promise<void> {
    try {
      logger.info(TAG, `Initializing database v${DB_VERSION}...`);
      this.rdbStore = await rdb.getRdbStore(context, STORE_CONFIG);
      await this.createTables();
      this.initialized = true;
      logger.info(TAG, 'Database initialized successfully, rdbStore is ready');
    } catch (err) {
      this.initialized = false;
      this.rdbStore = undefined;
      logger.error(TAG, `Database initialization failed: ${JSON.stringify(err)}`);
      throw this.toError(err);
    }
  }

  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RdbStore not initialized');
    }
    await this.rdbStore.executeSql(SQL_CREATE_TRAVELS);
    await this.rdbStore.executeSql(SQL_CREATE_MEMORY_NODES);
    await this.rdbStore.executeSql(SQL_CREATE_SYNC_QUEUE);
    await this.rdbStore.executeSql(SQL_CREATE_APP_SYNC_STATE);
    await this.rdbStore.executeSql(SQL_CREATE_USER_PROFILE);
    await this.ensureLatestSchema();
    logger.info(TAG, 'Tables created successfully');
  }

  private async ensureLatestSchema(): Promise<void> {
    const optionalSchemaUpdates: string[] = [
      SQL_ADD_TRAVEL_IS_PUBLIC,
      SQL_ADD_TRAVEL_OWNER_UID,
      SQL_ADD_TRAVEL_CLOUD_ID,
      SQL_ADD_TRAVEL_SYNC_STATUS,
      SQL_ADD_TRAVEL_DELETED_AT,
      SQL_ADD_TRAVEL_LAST_SYNCED_AT,
      SQL_ADD_TRAVEL_VERSION,
      SQL_ADD_TRAVEL_REPLAY_STYLE_KIT_ID,
      SQL_ADD_TRAVEL_REPLAY_BGM_ID,
      SQL_ADD_TRAVEL_REPLAY_FILTER_ID,
      SQL_ADD_TRAVEL_REPLAY_TRANSITION_TYPE,
      SQL_ADD_TRAVEL_REPLAY_ENABLE_RIPPLE,
      SQL_ADD_TRAVEL_REPLAY_ENABLE_ROUTE_ANIMATION,
      SQL_ADD_TRAVEL_REPLAY_ENABLE_BLUR_OVERLAY,
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
      SQL_ADD_MEMORY_NODE_VERSION,
      SQL_ADD_MEMORY_NODE_VISITED_AT,
      SQL_ADD_USER_PROFILE_OWNER_UID,
      SQL_ADD_SYNC_QUEUE_OWNER_UID
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

  async getPendingSyncQueueItems(ownerUid?: string): Promise<SyncQueueItem[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getStore();
      const predicates = RdbHelper.createPredicates('sync_queue');
      if (ownerUid !== undefined) {
        predicates.equalTo('owner_uid', ownerUid);
      }
      predicates.orderByAsc('created_at');
      resultSet = await store.query(predicates);
      const items: SyncQueueItem[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          items.push({
            id: resultSet.getDouble(resultSet.getColumnIndex('id')).toString(),
            ownerUid: resultSet.getString(resultSet.getColumnIndex('owner_uid')) ?? '',
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

  async getLatestSyncTimestamp(ownerUid?: string): Promise<number> {
    const lastPush = await this.getSyncState('last_push_at', ownerUid);
    const lastPull = await this.getSyncState('last_pull_at', ownerUid);
    return Math.max(lastPush, lastPull);
  }

  private toScopedSyncKey(key: string, ownerUid?: string): string {
    return ownerUid && ownerUid.length > 0 ? `${ownerUid}:${key}` : key;
  }

  async getSyncState(key: string, ownerUid?: string): Promise<number> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getStore();
      const predicates = RdbHelper.createPredicates('app_sync_state');
      predicates.equalTo('key', this.toScopedSyncKey(key, ownerUid));
      resultSet = await store.query(predicates);
      if (!resultSet.goToFirstRow()) {
        return 0;
      }
      const value = resultSet.getString(resultSet.getColumnIndex('value'));
      return Number(value ?? '0');
    } catch (err) {
      logger.error(TAG, `getSyncState failed: ${JSON.stringify(err)}`);
      return 0;
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (_) {}
      }
    }
  }

  async setSyncState(key: string, value: number, ownerUid?: string): Promise<void> {
    const store = await this.getStore();
    const scopedKey = this.toScopedSyncKey(key, ownerUid);
    const predicates = RdbHelper.createPredicates('app_sync_state');
    predicates.equalTo('key', scopedKey);
    const resultSet = await store.query(predicates);
    try {
      if (resultSet.goToFirstRow()) {
        await store.update({ value: value.toString() }, predicates);
      } else {
        await store.insert('app_sync_state', { key: scopedKey, value: value.toString() });
      }
    } finally {
      resultSet.close();
    }
  }

  async enqueueSyncItem(ownerUid: string, entityType: string, entityId: string, operation: string, payload: string): Promise<void> {
    const store = await this.getStore();
    await store.insert('sync_queue', {
      owner_uid: ownerUid,
      entity_type: entityType,
      entity_id: Number(entityId),
      operation: operation,
      payload: payload,
      created_at: RdbHelper.now(),
      retry_count: 0
    });
  }

  async removeSyncItems(entityType: string, entityId: string, ownerUid?: string): Promise<void> {
    const store = await this.getStore();
    const predicates = RdbHelper.createPredicates('sync_queue');
    predicates.equalTo('entity_type', entityType);
    predicates.equalTo('entity_id', Number(entityId));
    if (ownerUid !== undefined) {
      predicates.equalTo('owner_uid', ownerUid);
    }
    await store.delete(predicates);
  }

  async removeSyncItemById(id: string, ownerUid?: string): Promise<void> {
    const store = await this.getStore();
    const predicates = new rdb.RdbPredicates('sync_queue');
    predicates.equalTo('id', Number(id));
    if (ownerUid !== undefined) {
      predicates.equalTo('owner_uid', ownerUid);
    }
    await store.delete(predicates);
  }

  async clearSyncQueue(ownerUid?: string): Promise<void> {
    const store = await this.getStore();
    const predicates = RdbHelper.createPredicates('sync_queue');
    if (ownerUid !== undefined) {
      predicates.equalTo('owner_uid', ownerUid);
    }
    await store.delete(predicates);
  }

  /**
   * 注销账号：清除本地所有用户数据。
   * 不会重建数据库 schema，仅 truncate 各表。
   */
  async wipeAllUserData(): Promise<void> {
    const store = await this.getStore();
    const tables = ['memory_nodes', 'travels', 'sync_queue', 'app_sync_state', 'user_profile'];
    for (let i = 0; i < tables.length; i++) {
      const predicates = RdbHelper.createPredicates(tables[i]);
      try {
        await store.delete(predicates);
      } catch (err) {
        logger.error(TAG, `wipeAllUserData: failed to clear ${tables[i]}: ${JSON.stringify(err)}`);
      }
    }
    logger.info(TAG, 'wipeAllUserData done');
  }

  /** 保存用户 profile 到 user_profile 表（按 owner_uid 隔离） */
  async saveUserProfile(ownerUid: string, displayName: string, avatarPath: string, bio: string): Promise<void> {
    if (!ownerUid || ownerUid.length === 0) {
      throw new Error('saveUserProfile requires ownerUid');
    }
    logger.info(TAG, `saveUserProfile CALLED: ownerUid=${ownerUid}, displayName=${displayName}, avatarPath=${avatarPath}, bio=${bio}`);
    const store = await this.getStore();
    const predicates = RdbHelper.createPredicates('user_profile');
    predicates.equalTo('owner_uid', ownerUid);
    const resultSet = await store.query(predicates);
    try {
      if (resultSet.goToFirstRow()) {
        const rowId = resultSet.getLong(resultSet.getColumnIndex('id'));
        logger.info(TAG, `saveUserProfile: updating row id=${rowId}`);
        const updatePredicates = RdbHelper.createPredicates('user_profile');
        updatePredicates.equalTo('id', rowId);
        updatePredicates.equalTo('owner_uid', ownerUid);
        await store.update({
          owner_uid: ownerUid,
          display_name: displayName,
          avatar_path: avatarPath,
          bio: bio
        }, updatePredicates);
      } else {
        logger.info(TAG, `saveUserProfile: inserting new row for ownerUid=${ownerUid}`);
        await store.insert('user_profile', {
          owner_uid: ownerUid,
          display_name: displayName,
          avatar_path: avatarPath,
          bio: bio
        });
      }
      logger.info(TAG, `saveUserProfile SUCCESS: displayName=${displayName}`);
    } finally {
      resultSet.close();
    }
  }

  /** 从 user_profile 表加载 profile，返回 null 表示从未保存过 */
  async loadUserProfile(ownerUid: string): Promise<UserProfileRow | null> {
    if (!ownerUid || ownerUid.length === 0) {
      return null;
    }
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getStore();
      const predicates = RdbHelper.createPredicates('user_profile');
      predicates.equalTo('owner_uid', ownerUid);
      resultSet = await store.query(predicates);
      if (!resultSet.goToFirstRow()) {
        logger.info(TAG, `loadUserProfile: no row found for ownerUid=${ownerUid}, returning null`);
        return null;
      }
      const displayName: string = resultSet.getString(resultSet.getColumnIndex('display_name')) ?? '';
      const avatarPath: string = resultSet.getString(resultSet.getColumnIndex('avatar_path')) ?? '';
      const bio: string = resultSet.getString(resultSet.getColumnIndex('bio')) ?? '';
      if (!displayName && !avatarPath && !bio) {
        logger.info(TAG, 'loadUserProfile: row exists but all fields empty, returning null');
        return null;
      }
      logger.info(TAG, `loadUserProfile SUCCESS: ownerUid=${ownerUid}, displayName=${displayName}, avatarPath=${avatarPath}, bio=${bio}`);
      const row: UserProfileRow = { ownerUid: ownerUid, displayName: displayName, avatarPath: avatarPath, bio: bio };
      return row;
    } catch (err) {
      logger.error(TAG, `loadUserProfile FAILED: ${JSON.stringify(err)}`);
      return null;
    } finally {
      if (resultSet) {
        try { resultSet.close(); } catch (_) {}
      }
    }
  }

  /** 清除 user_profile */
  async clearUserProfile(ownerUid: string): Promise<void> {
    if (!ownerUid || ownerUid.length === 0) {
      return;
    }
    const store = await this.getStore();
    const predicates = RdbHelper.createPredicates('user_profile');
    predicates.equalTo('owner_uid', ownerUid);
    await store.delete(predicates);
    logger.info(TAG, `clearUserProfile done for ownerUid=${ownerUid}`);
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  setStoreForTesting(store: Object): void {
    this.rdbStore = store as rdb.RdbStore;
    this.initialized = true;
  }

  resetForTesting(): void {
    this.rdbStore = undefined;
    this.initialized = false;
    this.appContext = undefined;
    this.initPromise = null;
    RdbHelper.predicatesFactory = null;
    RdbHelper.nowProvider = null;
  }

  async close(): Promise<void> {
    if (this.rdbStore) {
      logger.info(TAG, 'Closing database');
      this.rdbStore = undefined;
      this.initialized = false;
    }
  }
}

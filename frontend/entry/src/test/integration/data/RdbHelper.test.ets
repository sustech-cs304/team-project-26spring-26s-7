import { describe, it, expect } from '@ohos/hypium';
import { RdbHelper } from '../../../main/ets/common/data/RdbHelper';
import {
  FakeStore,
  FieldValue,
  TimeSequence,
  row,
  setupRdbHelper,
} from './FakeRdbSupport';

export default function rdbHelperTest() {
  describe('RdbHelperTest', () => {
    it('throws when getStore is called before initialization', 0, async () => {
      const helper = RdbHelper.getInstance()
      helper.resetForTesting()

      let threw = false
      try {
        await helper.getStore()
      } catch (_err) {
        threw = true
      } finally {
        helper.resetForTesting()
      }

      expect(threw).assertTrue()
      expect(helper.isInitialized()).assertFalse()
    })

    it('writes and updates scoped sync state', 0, async () => {
      const store = new FakeStore()
      const helper = setupRdbHelper(store)

      try {
        await helper.setSyncState('last_push_at', 111, 'user-a')
        expect(await helper.getSyncState('last_push_at', 'user-a')).assertEqual(111)
        expect(await helper.getSyncState('last_push_at', 'user-b')).assertEqual(0)

        await helper.setSyncState('last_push_at', 222, 'user-a')
        expect(await helper.getSyncState('last_push_at', 'user-a')).assertEqual(222)
        expect(helper.isInitialized()).assertTrue()
      } finally {
        helper.resetForTesting()
      }
    })

    it('enqueues orders filters and removes sync queue items', 0, async () => {
      const store = new FakeStore()
      const helper = setupRdbHelper(store, new TimeSequence([300, 100, 200]))

      try {
        await helper.enqueueSyncItem('user-a', 'travel', '2', 'create', '{"id":2}')
        await helper.enqueueSyncItem('user-b', 'travel', '9', 'update', '{"id":9}')
        await helper.enqueueSyncItem('user-a', 'memory_node', '3', 'delete', '{"id":3}')

        const userAItems = await helper.getPendingSyncQueueItems('user-a')
        expect(userAItems.length).assertEqual(2)
        expect(userAItems[0].entityId).assertEqual('3')
        expect(userAItems[0].createdAt).assertEqual(200)
        expect(userAItems[1].entityId).assertEqual('2')
        expect(userAItems[1].createdAt).assertEqual(300)

        await helper.removeSyncItems('travel', '2', 'user-a')

        const remainingUserAItems = await helper.getPendingSyncQueueItems('user-a')
        expect(remainingUserAItems.length).assertEqual(1)
        expect(remainingUserAItems[0].entityType).assertEqual('memory_node')
        expect((await helper.getPendingSyncQueueItems()).length).assertEqual(2)
      } finally {
        helper.resetForTesting()
      }
    })

    it('wipes all user data across managed tables', 0, async () => {
      const store = new FakeStore()
      store.seedTable('memory_nodes', [row([new FieldValue('id', 1), new FieldValue('title', 'node-1')])])
      store.seedTable('travels', [row([new FieldValue('id', 2), new FieldValue('name', 'trip-1')])])
      store.seedTable('sync_queue', [row([
        new FieldValue('id', 3),
        new FieldValue('owner_uid', 'user-a'),
        new FieldValue('entity_type', 'travel'),
        new FieldValue('entity_id', 2)
      ])])
      store.seedTable('app_sync_state', [row([
        new FieldValue('key', 'user-a:last_push_at'),
        new FieldValue('value', '123')
      ])])
      store.seedTable('user_profile', [row([
        new FieldValue('id', 4),
        new FieldValue('owner_uid', 'user-a'),
        new FieldValue('display_name', 'Alice')
      ])])
      const helper = setupRdbHelper(store)

      try {
        await helper.wipeAllUserData()

        expect(store.getTableSize('memory_nodes')).assertEqual(0)
        expect(store.getTableSize('travels')).assertEqual(0)
        expect(store.getTableSize('sync_queue')).assertEqual(0)
        expect(store.getTableSize('app_sync_state')).assertEqual(0)
        expect(store.getTableSize('user_profile')).assertEqual(0)
      } finally {
        helper.resetForTesting()
      }
    })
  })
}

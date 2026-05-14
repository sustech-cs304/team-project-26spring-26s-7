import { describe, it, expect } from '@ohos/hypium';
import {
  MemoryNodeRepository,
  type CreateNodeInput,
  type UpdateNodeInput,
} from '../../../main/ets/common/data/MemoryNodeRepository';
import { TravelRepository } from '../../../main/ets/common/data/TravelRepository';
import type { Trip } from '../../../main/ets/common/service/types';
import {
  FakePredicates,
  FakeStore,
  FieldValue,
  TimeSequence,
  row,
  setupRdbHelper,
} from './FakeRdbSupport';

class StubTravelRepository extends TravelRepository {
  private trips: Trip[]

  constructor(trips: Trip[]) {
    super()
    this.trips = trips
  }

  async getTravelById(id: string): Promise<Trip | undefined> {
    for (let i = 0; i < this.trips.length; i++) {
      if (this.trips[i].id === id) {
        return this.trips[i]
      }
    }
    return undefined
  }
}

function createTrip(id: string): Trip {
  return {
    id,
    name: `Trip ${id}`,
    description: '',
    coverPhoto: '',
    isPublic: false,
    startDate: 1000,
    endDate: 2000,
    nodeIds: [],
    totalDistance: 0,
    createdAt: 3000,
    updatedAt: 4000,
    ownerUid: 'user-a',
    cloudId: '',
    syncStatus: 'synced',
    deletedAt: 0,
    lastSyncedAt: 0,
    version: 1
  }
}

function configureMemoryNodeRepository(trips: Trip[], nowValues?: number[]): void {
  MemoryNodeRepository.ownerUidProvider = async (): Promise<string> => {
    return 'user-a'
  }
  MemoryNodeRepository.predicatesFactory = (table: string): Object => {
    return new FakePredicates(table)
  }
  MemoryNodeRepository.travelRepositoryFactory = (): TravelRepository => {
    return new StubTravelRepository(trips)
  }
  if (nowValues) {
    const sequence = new TimeSequence(nowValues)
    MemoryNodeRepository.nowProvider = (): number => {
      return sequence.next()
    }
  } else {
    MemoryNodeRepository.nowProvider = null
  }
}

export default function memoryNodeRepositoryTest() {
  describe('MemoryNodeRepositoryTest', () => {
    it('creates a node with the next node order for its travel', 0, async () => {
      const store = new FakeStore()
      store.seedTable('memory_nodes', [row([
        new FieldValue('id', 1),
        new FieldValue('travel_id', 10),
        new FieldValue('latitude', 22.5),
        new FieldValue('longitude', 113.9),
        new FieldValue('title', 'Existing'),
        new FieldValue('poi_name', 'POI'),
        new FieldValue('description', 'desc'),
        new FieldValue('mood', ''),
        new FieldValue('tags', '[]'),
        new FieldValue('photos', '[]'),
        new FieldValue('photo_manifest', '[]'),
        new FieldValue('node_order', 0),
        new FieldValue('created_at', 100),
        new FieldValue('updated_at', 100),
        new FieldValue('owner_uid', 'user-a'),
        new FieldValue('cloud_id', ''),
        new FieldValue('sync_status', 'synced'),
        new FieldValue('deleted_at', 0),
        new FieldValue('last_synced_at', 0),
        new FieldValue('version', 1),
        new FieldValue('visited_at', 100)
      ])])
      const helper = setupRdbHelper(store)
      configureMemoryNodeRepository([createTrip('10')], [1000])
      const repo = new MemoryNodeRepository()
      const input: CreateNodeInput = {
        travelId: '10',
        title: 'New Node',
        latitude: 22.6,
        longitude: 114.0,
        poiName: 'New POI',
        description: 'New Desc',
        photos: ['/a.jpg'],
        tags: ['tag-a']
      }

      try {
        const id = await repo.createNode(input)
        const nodes = await repo.getNodesByTravelId('10')

        expect(id).assertEqual('2')
        expect(nodes.length).assertEqual(2)
        expect(nodes[1].id).assertEqual('2')
        expect(nodes[1].nodeOrder ?? -1).assertEqual(1)
        expect(nodes[1].title).assertEqual('New Node')
        expect(nodes[1].syncStatus ?? '').assertEqual('pending_create')
        expect(nodes[1].visitedAt ?? 0).assertEqual(1000)
      } finally {
        MemoryNodeRepository.resetTestingHooks()
        TravelRepository.resetTestingHooks()
        helper.resetForTesting()
      }
    })

    it('moves a node to another travel and appends its order there', 0, async () => {
      const store = new FakeStore()
      store.seedTable('memory_nodes', [
        row([
          new FieldValue('id', 5),
          new FieldValue('travel_id', 10),
          new FieldValue('latitude', 22.5),
          new FieldValue('longitude', 113.9),
          new FieldValue('title', 'Move Me'),
          new FieldValue('poi_name', 'POI'),
          new FieldValue('description', 'desc'),
          new FieldValue('mood', ''),
          new FieldValue('tags', '[]'),
          new FieldValue('photos', '["a.jpg"]'),
          new FieldValue('photo_manifest', '["a.jpg"]'),
          new FieldValue('node_order', 0),
          new FieldValue('created_at', 100),
          new FieldValue('updated_at', 100),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('cloud_id', 'cloud-node-5'),
          new FieldValue('sync_status', 'synced'),
          new FieldValue('deleted_at', 0),
          new FieldValue('last_synced_at', 0),
          new FieldValue('version', 4),
          new FieldValue('visited_at', 100)
        ]),
        row([
          new FieldValue('id', 8),
          new FieldValue('travel_id', 11),
          new FieldValue('latitude', 22.6),
          new FieldValue('longitude', 114.1),
          new FieldValue('title', 'Target Existing'),
          new FieldValue('poi_name', 'POI'),
          new FieldValue('description', 'desc'),
          new FieldValue('mood', ''),
          new FieldValue('tags', '[]'),
          new FieldValue('photos', '[]'),
          new FieldValue('photo_manifest', '[]'),
          new FieldValue('node_order', 2),
          new FieldValue('created_at', 100),
          new FieldValue('updated_at', 100),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('cloud_id', ''),
          new FieldValue('sync_status', 'synced'),
          new FieldValue('deleted_at', 0),
          new FieldValue('last_synced_at', 0),
          new FieldValue('version', 1),
          new FieldValue('visited_at', 100)
        ])
      ])
      const helper = setupRdbHelper(store)
      configureMemoryNodeRepository([createTrip('10'), createTrip('11')], [5000])
      const repo = new MemoryNodeRepository()
      const update: UpdateNodeInput = {
        travelId: '11',
        title: 'Moved Node'
      }

      try {
        const ok = await repo.updateNode('5', update)
        const node = await repo.getNodeById('5')

        expect(ok).assertTrue()
        expect(node?.travelId ?? '').assertEqual('11')
        expect(node?.title ?? '').assertEqual('Moved Node')
        expect(node?.nodeOrder ?? -1).assertEqual(3)
        expect(node?.syncStatus ?? '').assertEqual('pending_update')
        expect(node?.version ?? 0).assertEqual(5)
      } finally {
        MemoryNodeRepository.resetTestingHooks()
        TravelRepository.resetTestingHooks()
        helper.resetForTesting()
      }
    })

    it('reorders nodes and marks them as pending_reorder', 0, async () => {
      const store = new FakeStore()
      store.seedTable('memory_nodes', [
        row([
          new FieldValue('id', 1),
          new FieldValue('travel_id', 10),
          new FieldValue('latitude', 22.5),
          new FieldValue('longitude', 113.9),
          new FieldValue('title', 'Node 1'),
          new FieldValue('poi_name', 'POI'),
          new FieldValue('description', 'desc'),
          new FieldValue('mood', ''),
          new FieldValue('tags', '[]'),
          new FieldValue('photos', '[]'),
          new FieldValue('photo_manifest', '[]'),
          new FieldValue('node_order', 0),
          new FieldValue('created_at', 100),
          new FieldValue('updated_at', 100),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('cloud_id', ''),
          new FieldValue('sync_status', 'synced'),
          new FieldValue('deleted_at', 0),
          new FieldValue('last_synced_at', 0),
          new FieldValue('version', 1),
          new FieldValue('visited_at', 100)
        ]),
        row([
          new FieldValue('id', 2),
          new FieldValue('travel_id', 10),
          new FieldValue('latitude', 22.6),
          new FieldValue('longitude', 114.0),
          new FieldValue('title', 'Node 2'),
          new FieldValue('poi_name', 'POI'),
          new FieldValue('description', 'desc'),
          new FieldValue('mood', ''),
          new FieldValue('tags', '[]'),
          new FieldValue('photos', '[]'),
          new FieldValue('photo_manifest', '[]'),
          new FieldValue('node_order', 1),
          new FieldValue('created_at', 100),
          new FieldValue('updated_at', 100),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('cloud_id', ''),
          new FieldValue('sync_status', 'synced'),
          new FieldValue('deleted_at', 0),
          new FieldValue('last_synced_at', 0),
          new FieldValue('version', 1),
          new FieldValue('visited_at', 100)
        ]),
        row([
          new FieldValue('id', 3),
          new FieldValue('travel_id', 10),
          new FieldValue('latitude', 22.7),
          new FieldValue('longitude', 114.1),
          new FieldValue('title', 'Node 3'),
          new FieldValue('poi_name', 'POI'),
          new FieldValue('description', 'desc'),
          new FieldValue('mood', ''),
          new FieldValue('tags', '[]'),
          new FieldValue('photos', '[]'),
          new FieldValue('photo_manifest', '[]'),
          new FieldValue('node_order', 2),
          new FieldValue('created_at', 100),
          new FieldValue('updated_at', 100),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('cloud_id', ''),
          new FieldValue('sync_status', 'synced'),
          new FieldValue('deleted_at', 0),
          new FieldValue('last_synced_at', 0),
          new FieldValue('version', 1),
          new FieldValue('visited_at', 100)
        ])
      ])
      const helper = setupRdbHelper(store)
      configureMemoryNodeRepository([createTrip('10')], [8000, 8001, 8002])
      const repo = new MemoryNodeRepository()

      try {
        await repo.reorderNodes('10', ['3', '1', '2'])
        const nodes = await repo.getNodesByTravelId('10')

        expect(nodes.length).assertEqual(3)
        expect(nodes[0].id).assertEqual('3')
        expect(nodes[1].id).assertEqual('1')
        expect(nodes[2].id).assertEqual('2')
        expect(nodes[0].syncStatus ?? '').assertEqual('pending_reorder')
        expect(nodes[1].syncStatus ?? '').assertEqual('pending_reorder')
        expect(nodes[2].syncStatus ?? '').assertEqual('pending_reorder')
      } finally {
        MemoryNodeRepository.resetTestingHooks()
        TravelRepository.resetTestingHooks()
        helper.resetForTesting()
      }
    })
  })
}

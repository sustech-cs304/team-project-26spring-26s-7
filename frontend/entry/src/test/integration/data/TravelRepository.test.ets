import { describe, it, expect } from '@ohos/hypium';
import {
  TravelRepository,
  type CreateTravelInput,
  type UpdateTravelInput,
} from '../../../main/ets/common/data/TravelRepository';
import type { Trip } from '../../../main/ets/common/service/types';
import {
  FakePredicates,
  FakeStore,
  FieldValue,
  TimeSequence,
  row,
  setupRdbHelper,
} from './FakeRdbSupport';

function configureTravelRepository(ownerUid: string, nowValues?: number[]): void {
  TravelRepository.ownerUidProvider = async (): Promise<string> => {
    return ownerUid
  }
  TravelRepository.predicatesFactory = (table: string): Object => {
    return new FakePredicates(table)
  }
  if (nowValues) {
    const sequence = new TimeSequence(nowValues)
    TravelRepository.nowProvider = (): number => {
      return sequence.next()
    }
  } else {
    TravelRepository.nowProvider = null
  }
}

function createTripRow(
  id: number,
  ownerUid: string,
  cloudId: string,
  syncStatus: string,
  version: number
): Trip {
  return {
    id: `${id}`,
    name: `Trip ${id}`,
    description: '',
    coverPhoto: `/covers/${id}.jpg`,
    isPublic: false,
    startDate: 1000 + id,
    endDate: 2000 + id,
    nodeIds: [],
    totalDistance: 0,
    createdAt: 3000 + id,
    updatedAt: 4000 + id,
    ownerUid,
    cloudId,
    syncStatus,
    deletedAt: 0,
    lastSyncedAt: 0,
    version,
    replayStyleKitId: 'style-a',
    replayBgmId: 'bgm-a',
    replayFilterId: 'filter-a',
    replayTransitionType: 'fade',
    replayEnableRipple: false,
    replayEnableRouteAnimation: true,
    replayEnableBlurOverlay: false
  }
}

export default function travelRepositoryTest() {
  describe('TravelRepositoryTest', () => {
    it('creates and loads owner-scoped travels with replay preferences', 0, async () => {
      const store = new FakeStore()
      const helper = setupRdbHelper(store)
      configureTravelRepository('user-a', [1000])
      const repo = new TravelRepository()
      const input: CreateTravelInput = {
        name: 'Summer Trip',
        coverImageUri: '/covers/summer.jpg',
        isPublic: true,
        startDate: 1710000000,
        endDate: 1710086400,
        replayStyleKitId: 'minimal_white',
        replayBgmId: 'city_lights_lofi',
        replayFilterId: 'warm',
        replayTransitionType: 'slide',
        replayEnableRipple: true,
        replayEnableRouteAnimation: false,
        replayEnableBlurOverlay: true
      }

      try {
        const id = await repo.createTravel(input)
        const trip = await repo.getTravelById(id)
        const allTrips = await repo.getAllTravels()

        expect(id).assertEqual('1')
        expect(trip?.name ?? '').assertEqual('Summer Trip')
        expect(trip?.isPublic ?? false).assertTrue()
        expect(trip?.replayStyleKitId ?? '').assertEqual('minimal_white')
        expect(trip?.replayTransitionType ?? '').assertEqual('slide')
        expect(trip?.replayEnableRipple ?? false).assertTrue()
        expect(trip?.syncStatus ?? '').assertEqual('pending_create')
        expect(allTrips.length).assertEqual(1)
      } finally {
        TravelRepository.resetTestingHooks()
        helper.resetForTesting()
      }
    })

    it('updates cloud-backed travels with pending_update and bumped version', 0, async () => {
      const store = new FakeStore()
      store.seedTable('travels', [row([
        new FieldValue('id', 5),
        new FieldValue('name', 'Trip 5'),
        new FieldValue('cover_image_uri', '/covers/5.jpg'),
        new FieldValue('is_public', 0),
        new FieldValue('start_date', 100),
        new FieldValue('end_date', 200),
        new FieldValue('created_at', 300),
        new FieldValue('updated_at', 400),
        new FieldValue('owner_uid', 'user-a'),
        new FieldValue('cloud_id', 'cloud-5'),
        new FieldValue('sync_status', 'synced'),
        new FieldValue('deleted_at', 0),
        new FieldValue('last_synced_at', 0),
        new FieldValue('version', 2),
        new FieldValue('replay_style_kit_id', 'style-a'),
        new FieldValue('replay_bgm_id', 'bgm-a'),
        new FieldValue('replay_filter_id', 'filter-a'),
        new FieldValue('replay_transition_type', 'fade'),
        new FieldValue('replay_enable_ripple', 0),
        new FieldValue('replay_enable_route_animation', 1),
        new FieldValue('replay_enable_blur_overlay', 0)
      ])])
      const helper = setupRdbHelper(store)
      configureTravelRepository('user-a', [5000])
      const repo = new TravelRepository()
      const update: UpdateTravelInput = {
        name: 'Updated Trip 5',
        isPublic: true
      }

      try {
        const ok = await repo.updateTravel('5', update)
        const trip = await repo.getTravelById('5')

        expect(ok).assertTrue()
        expect(trip?.name ?? '').assertEqual('Updated Trip 5')
        expect(trip?.isPublic ?? false).assertTrue()
        expect(trip?.syncStatus ?? '').assertEqual('pending_update')
        expect(trip?.version ?? 0).assertEqual(3)
        expect(trip?.updatedAt ?? 0).assertEqual(5000)
      } finally {
        TravelRepository.resetTestingHooks()
        helper.resetForTesting()
      }
    })

    it('deletes child nodes before removing the travel row', 0, async () => {
      const store = new FakeStore()
      store.seedTable('travels', [row([
        new FieldValue('id', 7),
        new FieldValue('name', 'Trip 7'),
        new FieldValue('cover_image_uri', '/covers/7.jpg'),
        new FieldValue('is_public', 0),
        new FieldValue('start_date', 100),
        new FieldValue('end_date', 200),
        new FieldValue('created_at', 300),
        new FieldValue('updated_at', 400),
        new FieldValue('owner_uid', 'user-a'),
        new FieldValue('cloud_id', ''),
        new FieldValue('sync_status', 'pending_create'),
        new FieldValue('deleted_at', 0),
        new FieldValue('last_synced_at', 0),
        new FieldValue('version', 1)
      ])])
      store.seedTable('memory_nodes', [
        row([
          new FieldValue('id', 21),
          new FieldValue('travel_id', 7),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('deleted_at', 0)
        ]),
        row([
          new FieldValue('id', 22),
          new FieldValue('travel_id', 7),
          new FieldValue('owner_uid', 'user-a'),
          new FieldValue('deleted_at', 0)
        ])
      ])
      const helper = setupRdbHelper(store)
      configureTravelRepository('user-a')
      const repo = new TravelRepository()

      try {
        const ok = await repo.deleteTravel('7')

        expect(ok).assertTrue()
        expect(store.getTableSize('travels')).assertEqual(0)
        expect(store.getTableSize('memory_nodes')).assertEqual(0)
      } finally {
        TravelRepository.resetTestingHooks()
        helper.resetForTesting()
      }
    })
  })
}

import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { geoLocationManager } from '@kit.LocationKit'
import { DEFAULT_MAP_LATITUDE, DEFAULT_MAP_LONGITUDE } from './Constants'
import { logger } from './Logger'

const MAP_PREFERRED_LATITUDE_KEY = 'mapPreferredLatitude'
const MAP_PREFERRED_LONGITUDE_KEY = 'mapPreferredLongitude'
const MAP_PREFERRED_LABEL_KEY = 'mapPreferredLabel'
const MAP_PREFERRED_SOURCE_KEY = 'mapPreferredSource'
const MAP_PREFERRED_TIMESTAMP_KEY = 'mapPreferredTimestamp'
const MAP_CURRENT_LATITUDE_KEY = 'mapCurrentLatitude'
const MAP_CURRENT_LONGITUDE_KEY = 'mapCurrentLongitude'
const MAP_CURRENT_PENDING_KEY = 'mapCurrentLocationPending'
const MAP_CURRENT_ERROR_KEY = 'mapCurrentLocationError'
const MAP_CURRENT_TIMESTAMP_KEY = 'mapCurrentLocationTimestamp'

export type MapPreferenceSource = 'fallback' | 'history' | 'picked' | 'device'

export interface MapCenter {
  latitude: number
  longitude: number
}

export interface MapPreferenceState extends MapCenter {
  label: string
  source: MapPreferenceSource
  timestamp: number
}

interface PermissionRequestResultLike {
  authResults?: number[]
}

interface LocationLike {
  latitude: number
  longitude: number
}

export function getDefaultMapCenter(): MapCenter {
  return {
    latitude: DEFAULT_MAP_LATITUDE,
    longitude: DEFAULT_MAP_LONGITUDE
  }
}

export function isValidMapCenter(latitude: number, longitude: number): boolean {
  return Number.isFinite(latitude) && Number.isFinite(longitude) && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
}

export function getStoredPreferredMapCenter(): MapPreferenceState {
  const fallback = getDefaultMapCenter()
  const latitude = AppStorage.get<number>(MAP_PREFERRED_LATITUDE_KEY) ?? fallback.latitude
  const longitude = AppStorage.get<number>(MAP_PREFERRED_LONGITUDE_KEY) ?? fallback.longitude
  const label = AppStorage.get<string>(MAP_PREFERRED_LABEL_KEY) ?? ''
  const source = (AppStorage.get<string>(MAP_PREFERRED_SOURCE_KEY) as MapPreferenceSource) ?? 'fallback'
  const timestamp = AppStorage.get<number>(MAP_PREFERRED_TIMESTAMP_KEY) ?? 0

  if (!isValidMapCenter(latitude, longitude)) {
    return {
      latitude: fallback.latitude,
      longitude: fallback.longitude,
      label: '',
      source: 'fallback',
      timestamp: 0
    }
  }

  return { latitude, longitude, label, source, timestamp }
}

export function hasStoredPreferredMapCenter(): boolean {
  return getStoredPreferredMapCenter().source !== 'fallback'
}

export function savePreferredMapCenter(latitude: number, longitude: number, label: string, source: MapPreferenceSource): void {
  if (!isValidMapCenter(latitude, longitude)) {
    return
  }
  const timestamp = Date.now()
  AppStorage.setOrCreate(MAP_PREFERRED_LATITUDE_KEY, latitude)
  AppStorage.setOrCreate(MAP_PREFERRED_LONGITUDE_KEY, longitude)
  AppStorage.setOrCreate(MAP_PREFERRED_LABEL_KEY, label)
  AppStorage.setOrCreate(MAP_PREFERRED_SOURCE_KEY, source)
  AppStorage.setOrCreate(MAP_PREFERRED_TIMESTAMP_KEY, timestamp)
}

export function saveCurrentLocationState(latitude: number, longitude: number): void {
  if (!isValidMapCenter(latitude, longitude)) {
    return
  }
  AppStorage.setOrCreate(MAP_CURRENT_LATITUDE_KEY, latitude)
  AppStorage.setOrCreate(MAP_CURRENT_LONGITUDE_KEY, longitude)
  AppStorage.setOrCreate(MAP_CURRENT_TIMESTAMP_KEY, Date.now())
  AppStorage.setOrCreate(MAP_CURRENT_ERROR_KEY, '')
}

export function setMapCurrentLocationPending(pending: boolean): void {
  AppStorage.setOrCreate(MAP_CURRENT_PENDING_KEY, pending)
}

export function setMapCurrentLocationError(message: string): void {
  AppStorage.setOrCreate(MAP_CURRENT_ERROR_KEY, message)
}

export function resolveMapCenterFromNodes<T extends MapCenter>(nodes: T[]): MapCenter | null {
  if (nodes.length === 0) {
    return null
  }
  let latitudeSum = 0
  let longitudeSum = 0
  let validCount = 0
  for (const node of nodes) {
    if (!isValidMapCenter(node.latitude, node.longitude)) {
      continue
    }
    latitudeSum += node.latitude
    longitudeSum += node.longitude
    validCount += 1
  }
  if (validCount === 0) {
    return null
  }
  return {
    latitude: latitudeSum / validCount,
    longitude: longitudeSum / validCount
  }
}

export async function requestCurrentLocation(hostContext: Object | undefined): Promise<MapCenter | null> {
  if (!hostContext) {
    setMapCurrentLocationError('context-unavailable')
    return null
  }
  setMapCurrentLocationPending(true)
  setMapCurrentLocationError('')
  try {
    const context = hostContext as common.UIAbilityContext
    const atManager = abilityAccessCtrl.createAtManager()
    const permissionResult = await atManager.requestPermissionsFromUser(context, [
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ]) as PermissionRequestResultLike

    const authResults = permissionResult.authResults ?? []
    if (authResults.length > 0 && authResults.every((result: number) => result !== 0)) {
      setMapCurrentLocationError('permission-denied')
      return null
    }

    try {
      const location = await geoLocationManager.getCurrentLocation() as LocationLike
      if (isValidMapCenter(location.latitude, location.longitude)) {
        saveCurrentLocationState(location.latitude, location.longitude)
        return { latitude: location.latitude, longitude: location.longitude }
      }
    } catch (error) {
      logger.warn('MapLocationPreference', `getCurrentLocation failed: ${JSON.stringify(error)}`)
    }

    try {
      const lastLocation = await geoLocationManager.getLastLocation() as LocationLike
      if (isValidMapCenter(lastLocation.latitude, lastLocation.longitude)) {
        saveCurrentLocationState(lastLocation.latitude, lastLocation.longitude)
        return { latitude: lastLocation.latitude, longitude: lastLocation.longitude }
      }
    } catch (error) {
      logger.warn('MapLocationPreference', `getLastLocation failed: ${JSON.stringify(error)}`)
    }

    setMapCurrentLocationError('location-unavailable')
    return null
  } catch (error) {
    logger.warn('MapLocationPreference', `requestCurrentLocation failed: ${JSON.stringify(error)}`)
    setMapCurrentLocationError('location-error')
    return null
  } finally {
    setMapCurrentLocationPending(false)
  }
}

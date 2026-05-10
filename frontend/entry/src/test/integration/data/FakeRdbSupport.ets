import { RdbHelper } from '../../../main/ets/common/data/RdbHelper';

export class FieldValue {
  key: string
  value: string | number | boolean

  constructor(key: string, value: string | number | boolean) {
    this.key = key
    this.value = value
  }
}

export class RowRecord {
  fields: FieldValue[] = []

  constructor(fields: FieldValue[] = []) {
    for (let i = 0; i < fields.length; i++) {
      this.fields.push(new FieldValue(fields[i].key, fields[i].value))
    }
  }

  get(key: string): string | number | boolean | undefined {
    for (let i = 0; i < this.fields.length; i++) {
      if (this.fields[i].key === key) {
        return this.fields[i].value
      }
    }
    return undefined
  }

  set(key: string, value: string | number | boolean): void {
    for (let i = 0; i < this.fields.length; i++) {
      if (this.fields[i].key === key) {
        this.fields[i].value = value
        return
      }
    }
    this.fields.push(new FieldValue(key, value))
  }

  clone(): RowRecord {
    return new RowRecord(this.fields)
  }
}

class TableData {
  name: string
  rows: RowRecord[] = []

  constructor(name: string, rows: RowRecord[] = []) {
    this.name = name
    for (let i = 0; i < rows.length; i++) {
      this.rows.push(rows[i].clone())
    }
  }
}

class FilterEntry {
  field: string
  value: string | number

  constructor(field: string, value: string | number) {
    this.field = field
    this.value = value
  }
}

export class FakePredicates {
  table: string
  filters: FilterEntry[] = []
  orderByField: string = ''
  descending: boolean = false

  constructor(table: string) {
    this.table = table
  }

  equalTo(field: string, value: string | number): FakePredicates {
    this.filters.push(new FilterEntry(field, value))
    return this
  }

  orderByAsc(field: string): FakePredicates {
    this.orderByField = field
    this.descending = false
    return this
  }

  orderByDesc(field: string): FakePredicates {
    this.orderByField = field
    this.descending = true
    return this
  }
}

export class FakeResultSet {
  private rows: RowRecord[]
  private columns: string[] = []
  private index: number = -1

  constructor(rows: RowRecord[]) {
    this.rows = rows
    if (rows.length > 0) {
      const first = rows[0]
      for (let i = 0; i < first.fields.length; i++) {
        this.columns.push(first.fields[i].key)
      }
    }
  }

  goToFirstRow(): boolean {
    if (this.rows.length === 0) {
      this.index = -1
      return false
    }
    this.index = 0
    return true
  }

  goToNextRow(): boolean {
    if (this.index + 1 >= this.rows.length) {
      return false
    }
    this.index += 1
    return true
  }

  getColumnIndex(name: string): number {
    for (let i = 0; i < this.columns.length; i++) {
      if (this.columns[i] === name) {
        return i
      }
    }
    this.columns.push(name)
    return this.columns.length - 1
  }

  getDouble(index: number): number {
    const value = this.getValue(index)
    if (typeof value === 'number') {
      return value
    }
    return Number(value ?? 0)
  }

  getLong(index: number): number {
    return this.getDouble(index)
  }

  getString(index: number): string | undefined {
    const value = this.getValue(index)
    if (value === undefined) {
      return undefined
    }
    return `${value}`
  }

  close(): void {}

  private getValue(index: number): string | number | boolean | undefined {
    if (this.index < 0 || this.index >= this.rows.length) {
      return undefined
    }
    if (index < 0 || index >= this.columns.length) {
      return undefined
    }
    return this.rows[this.index].get(this.columns[index])
  }
}

export class FakeStore {
  private tables: TableData[] = []
  private nextId: number = 1

  seedTable(name: string, rows: RowRecord[]): void {
    const table = this.getOrCreateTable(name)
    table.rows = []
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i].clone()
      table.rows.push(row)
      const idValue = row.get('id')
      if (typeof idValue === 'number' && idValue >= this.nextId) {
        this.nextId = idValue + 1
      }
    }
  }

  getTableSize(name: string): number {
    return this.getOrCreateTable(name).rows.length
  }

  async executeSql(_sql: string): Promise<void> {}

  async query(predicates: Object): Promise<Object> {
    const fakePredicates = predicates as FakePredicates
    const source = this.getOrCreateTable(fakePredicates.table).rows
    const resultRows: RowRecord[] = []
    for (let i = 0; i < source.length; i++) {
      if (this.matches(source[i], fakePredicates)) {
        resultRows.push(source[i].clone())
      }
    }
    if (fakePredicates.orderByField.length > 0) {
      resultRows.sort((left: RowRecord, right: RowRecord): number => {
        const delta = Number(left.get(fakePredicates.orderByField) ?? 0) -
          Number(right.get(fakePredicates.orderByField) ?? 0)
        return fakePredicates.descending ? -delta : delta
      })
    }
    return new FakeResultSet(resultRows)
  }

  async update(values: Object, predicates: Object): Promise<number> {
    const fakePredicates = predicates as FakePredicates
    const rows = this.getOrCreateTable(fakePredicates.table).rows
    const keys = Object.keys(values)
    let count = 0
    for (let i = 0; i < rows.length; i++) {
      if (!this.matches(rows[i], fakePredicates)) {
        continue
      }
      for (let j = 0; j < keys.length; j++) {
        const key = keys[j]
        const value = Reflect.get(values, key) as string | number | boolean | undefined
        if (value !== undefined) {
          rows[i].set(key, value)
        }
      }
      count += 1
    }
    return count
  }

  async insert(table: string, values: Object): Promise<number> {
    const row = new RowRecord()
    const keys = Object.keys(values)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value = Reflect.get(values, key) as string | number | boolean | undefined
      if (value !== undefined) {
        row.set(key, value)
      }
    }
    if (typeof row.get('id') !== 'number') {
      row.set('id', this.nextId)
      this.nextId += 1
    }
    this.getOrCreateTable(table).rows.push(row)
    return Number(row.get('id') ?? 0)
  }

  async delete(predicates: Object): Promise<number> {
    const fakePredicates = predicates as FakePredicates
    const table = this.getOrCreateTable(fakePredicates.table)
    const kept: RowRecord[] = []
    let deleted = 0
    for (let i = 0; i < table.rows.length; i++) {
      if (this.matches(table.rows[i], fakePredicates)) {
        deleted += 1
      } else {
        kept.push(table.rows[i])
      }
    }
    table.rows = kept
    return deleted
  }

  private matches(row: RowRecord, predicates: FakePredicates): boolean {
    for (let i = 0; i < predicates.filters.length; i++) {
      const filter = predicates.filters[i]
      if (row.get(filter.field) !== filter.value) {
        return false
      }
    }
    return true
  }

  private getOrCreateTable(name: string): TableData {
    for (let i = 0; i < this.tables.length; i++) {
      if (this.tables[i].name === name) {
        return this.tables[i]
      }
    }
    const table = new TableData(name)
    this.tables.push(table)
    return table
  }
}

export class TimeSequence {
  values: number[] = []

  constructor(values: number[] = []) {
    for (let i = 0; i < values.length; i++) {
      this.values.push(values[i])
    }
  }

  next(): number {
    if (this.values.length === 0) {
      return 0
    }
    const value = this.values[0]
    this.values.splice(0, 1)
    return value
  }
}

export function row(fields: FieldValue[]): RowRecord {
  return new RowRecord(fields)
}

export function setupRdbHelper(store: FakeStore, timeSequence?: TimeSequence): RdbHelper {
  const helper = RdbHelper.getInstance()
  helper.resetForTesting()
  helper.setStoreForTesting(store)
  RdbHelper.predicatesFactory = (table: string): Object => {
    return new FakePredicates(table)
  }
  if (timeSequence) {
    RdbHelper.nowProvider = (): number => {
      return timeSequence.next()
    }
  }
  return helper
}

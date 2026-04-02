  ---
  数据库关系设计说明                                                                                                                                          
                                                                                                                                                                1. 现有数据模型对比                                                                                                                                         
                                                                                                                                                              
  ┌─────────────┬──────────────┬─────────────────────────────────────────────────────────────────────────┐                                                    
  │  数据模型   │     用途     │                                  字段                                   │                                                    
  ├─────────────┼──────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ Trip        │ 旅行路线摘要 │ id, name, nodeIds[], totalDistance, startDate, endDate                  │
  ├─────────────┼──────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ MemoryNode  │ 单个记忆节点 │ id, travelId, title, content, latitude, longitude, photos[], mood, tags │
  ├─────────────┼──────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ ReplayNode  │ 回放专用节点 │ id, position, photoUri, title, note, noteShort, timestamp, order        │
  ├─────────────┼──────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ ReplayRoute │ 回放专用路线 │ id, name, nodes[], totalDistance, duration                              │
  └─────────────┴──────────────┴─────────────────────────────────────────────────────────────────────────┘

  2. 数据流转关系

  ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
  │  Trip (路线)    │────▶│  MemoryNode[]    │────▶│  ReplayRoute    │
  │  - id           │     │  (原始数据)      │     │  (回放数据)     │
  │  - nodeIds[]    │     │  - travelId      │     │  - nodes[]      │
  └─────────────────┘     └──────────────────┘     └─────────────────┘
                                 │                         │
                                 │                         ▼
                                 │                  动画播放用
                                 ▼
                          数据库存储结构

  3. 转换逻辑（占位接口）

  RouteGenerator 接口已定义（types.ets 第 222 行）：

  export interface RouteGenerator {
    /**
     * 从记忆节点生成回放路线
     * @param nodes 记忆节点数组（来自 MemoryNodeRepository）
     * @returns 回放路线
     */
    generateFromNodes(nodes: MemoryNode[]): ReplayRoute
  }

  4. 数据库表设计建议

  Trip 表：
  CREATE TABLE trip (
    id TEXT PRIMARY KEY,
    name TEXT,
    description TEXT,
    coverPhoto TEXT,
    startDate INTEGER,
    endDate INTEGER,
    totalDistance REAL,
    createdAt INTEGER,
    updatedAt INTEGER
  )

  MemoryNode 表：
  CREATE TABLE memory_node (
    id TEXT PRIMARY KEY,
    travelId TEXT,           -- 关联 trip.id
    title TEXT,
    content TEXT,
    latitude REAL,
    longitude REAL,
    poiName TEXT,
    photos TEXT,             -- JSON 数组存储
    mood TEXT,
    tags TEXT,               -- JSON 数组存储
    createdAt INTEGER,
    updatedAt INTEGER,
    FOREIGN KEY (travelId) REFERENCES trip(id)
  )

  5. 当前占位代码位置

  ┌───────────────────────────┬─────────────────┬───────────────────────────────────────────────────────────┐
  │           文件            │    占位代码     │                           说明                            │
  ├───────────────────────────┼─────────────────┼───────────────────────────────────────────────────────────┤
  │ TripReplayPage.ets:67-108 │ aboutToAppear() │ 硬编码 mockRoute，注释写明"后续替换为从 RDB 加载"         │
  ├───────────────────────────┼─────────────────┼───────────────────────────────────────────────────────────┤
  │ TripDetailPage.ets:84-89  │ aboutToAppear() │ 获取 tripId，TODO 注释"从本地 RDB 加载旅行数据和关联节点" │
  ├───────────────────────────┼─────────────────┼───────────────────────────────────────────────────────────┤
  │ types.ets:222-228         │ RouteGenerator  │ 接口已定义，等待队友实现                                  │
  └───────────────────────────┴─────────────────┴───────────────────────────────────────────────────────────┘

  6. 后续集成步骤

  当数据库功能完成后，只需：

  1. 实现 RouteGenerator.generateFromNodes()：
  class DefaultRouteGenerator implements RouteGenerator {
    generateFromNodes(nodes: MemoryNode[]): ReplayRoute {
      return {
        id: nodes[0]?.travelId || '',
        name: '',  // 从 Trip 表获取
        nodes: nodes.map((n, i) => new ReplayNode(
          n.id,
          n.latitude,
          n.longitude,
          n.photos[0],  // 取第一张照片
          n.title,
          n.content,
          n.content.substring(0, 20) + '...',
          n.createdAt,
          i
        )),
        totalDistance: 0,  // 从 Trip 表获取
        duration: 0
      }
    }
  }

  2. 修改 TripReplayPage.aboutToAppear()：
  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      // 从 RDB 加载 MemoryNode[]
      const nodes = await MemoryNodeRepository.getByTripId(params.tripId)
      // 转换为 ReplayRoute
      this.replayRoute = new DefaultRouteGenerator().generateFromNodes(nodes)
    }
  }

  ---
  总结：接口已预留，转换逻辑待实现。数据库完成后，集成工作量约 1-2 小时。
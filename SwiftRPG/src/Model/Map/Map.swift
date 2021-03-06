//
//  Map.swift
//  SwiftRPG
//
//  Created by 兎澤佑 on 2016/02/22.
//  Copyright © 2016年 兎澤佑. All rights reserved.
//

import Foundation
import SpriteKit

open class Map {
    /// タイルシート
    fileprivate(set) var sheet: TileSheet? = nil
    
    /// マップオブジェクトの配置を保持しておくディクショナリ
    fileprivate var placement: Dictionary<TileCoordinate, [MapObject]> = [:]
    
    /// オブジェクトのみ保持するディクショナリ
    fileprivate var objects: Dictionary<TileCoordinate, [Object]> = [:]
    
    ///  コンストラクタ
    ///
    ///  - parameter mapName:     マップである JSON ファイルの名前
    ///  - parameter frameWidth:  フレームの幅
    ///  - parameter frameHeight: フレームの高さ
    ///
    ///  - returns:
    init?(mapName: String,
          frameWidth: CGFloat,
          frameHeight: CGFloat)
    {
        let parser: TiledMapJsonParser
        do {
            parser = try TiledMapJsonParser(fileName: mapName)
        } catch ParseError.illegalJsonFormat {
            print("Invalid JSON format in \(mapName)")
            return nil
        } catch ParseError.jsonFileNotFound {
            print("JSON file \(mapName) is not found")
            return nil
        } catch {
            return nil
        }

        let tiles: Dictionary<TileCoordinate, Tile>
        var objects: Dictionary<TileCoordinate, [Object]>
        do {
            let cols, rows: Int
            (cols, rows) = try parser.getLayerSize()
            let tileProperties = try parser.getTileProperties()
            let tileSets = try parser.getTileSets()
            let collisionLayer = try parser.getInfoFromLayer(cols, layerTileRows: rows, kind: .collision)
            let tileLayer = try parser.getInfoFromLayer(cols, layerTileRows: rows, kind: .tile)
            let objectLayer = try parser.getInfoFromLayer(cols, layerTileRows: rows, kind: .object)
            tiles = try Tile.createTiles(rows,
                                         cols: cols,
                                         properties: tileProperties,
                                         tileSets: tileSets,
                                         collisionPlacement: collisionLayer,
                                         tilePlacement: tileLayer)
            objects = try Object.createObjects(tiles,
                                               properties: tileProperties,
                                               tileSets: tileSets,
                                               objectPlacement: objectLayer)
        } catch ParseError.invalidValueError(let string) {
            print(string)
            return nil
        } catch ParseError.swiftyJsonError(let errors) {
            for error in errors { print(error!) }
            return nil
        } catch MapObjectError.failedToGenerate(let string) {
            print(string)
            return nil
        } catch {
            return nil
        }

        let sheet = TileSheet(parser: parser,
                              frameWidth: frameWidth,
                              frameHeight: frameHeight,
                              tiles: tiles,
                              objects: objects)
        self.sheet = sheet!

        for (coordinate, tile) in tiles {
            self.placement[coordinate] = [tile]
        }

        for (coordinate, objectsOnTile) in objects {
            for objectOnTile in objectsOnTile {
                self.placement[coordinate]!.append(objectOnTile)
            }
        }

        self.objects = objects
    }

    func addSheetTo(_ scene: SKScene) {
        self.sheet!.addTo(scene)
    }

    ///  名前からオブジェクトを取得する
    ///
    ///  - parameter name: オブジェクト名
    ///
    ///  - returns: 取得したオブジェクト．存在しなければ nil
    func getObjectByName(_ name: String) -> Object? {
        for (_, mapObjects) in placement {
            for object in mapObjects {
                if let obj = object as? Object {
                    if obj.name == name { return obj }
                }
            }
        }
        return nil
    }

    func getObjectCoordinateByName(_ name: String) -> TileCoordinate? {
        for (coordinate, mapObjects) in placement {
            for object in mapObjects {
                if let obj = object as? Object {
                    if obj.name == name { return coordinate }
                }
            }
        }
        return nil
    }

    func setObject(_ object: Object) {
        let coordinate = TileCoordinate.getTileCoordinateFromSheetCoordinate(object.position)

        if objects[coordinate] == nil {
            objects[coordinate] = [object]
        } else {
            objects[coordinate]!.append(object)
        }
        placement[coordinate]!.append(object)

        self.sheet?.addObjectToSheet(object)
    }

    ///  配置されたオブジェクトを取得する
    ///
    ///  - parameter coordinate: タイル座標
    ///
    ///  - returns: 配置されたオブジェクト群
    func getMapObjectsOn(_ coordinate: TileCoordinate) -> [MapObject]? {
        return self.placement[coordinate]
    }

    ///  配置されたイベントを取得する
    ///
    ///  - parameter coordinate: イベントを取得するタイル座標
    ///
    ///  - returns: 取得したイベント群
    func getEventsOn(_ coordinate: TileCoordinate) -> [EventListener] {
        var events: [EventListener] = []

        if let mapObjects = self.placement[coordinate] {
            for mapObject in mapObjects {
                for event in mapObject.events {
                    events.append(event)
                }
            }
        }
        
        return events
    }

    ///  タイル座標の通行可否を判定する
    ///
    ///  - parameter coordinate: 判定対象のタイル座標
    ///
    ///  - returns: 通行可なら true, 通行不可なら false
    func canPass(_ coordinate: TileCoordinate) -> Bool {
        if let objects = self.placement[coordinate] {
            for object in objects {
                if object.hasCollision { return false }
            }
        }
        return true
    }

    ///  オブジェクトの位置情報を，実際のSKSpriteNodeの位置から更新する
    ///
    ///  - parameter object:        更新対象のオブジェクト
    func updateObjectPlacement(_ object: Object) {
        let departure   = self.getObjectCoordinateByName(object.name)!
        let destination = TileCoordinate.getTileCoordinateFromSheetCoordinate(object.getRealTimePosition())
        
        var objectIndex: Int? = nil
        let mapObjects = self.placement[departure]
        for (index, mapObject) in mapObjects!.enumerated() {
            if let obj = mapObject as? Object {
                if obj.name == object.name {
                    objectIndex = index
                    break
                }
            }
        }
        
        if objectIndex == nil { return }
        self.placement[departure]!.remove(at: objectIndex!)
        self.placement[destination]!.append(object)
        print(destination.description)
    }

    ///  オブジェクトのZ方向の位置を更新する
    func updateObjectsZPosition() {
        var objects: [(Object, CGFloat)] = []
        
        for objectsOnTile in self.objects.values {
            for object in objectsOnTile {
                objects.append((object, object.getRealTimePosition().y))
            }
        }
        
        // Y座標に基づいてオブジェクトを並べ替え，zPosition を更新する
        objects.sort { $0.1 > $1.1 }
        let base = zPositionTable.BASE_OBJECT_POSITION
        var incremental: CGFloat = 0.0
        for (obj, _) in objects {
            obj.setZPosition(base + incremental)
            incremental += 1
        }
    }
}

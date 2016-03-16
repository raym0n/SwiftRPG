//
//  GameSceneEvent.swift
//  RunTowardTheLight
//
//  Created by 兎澤佑 on 2015/09/28.
//  Copyright © 2015年 兎澤佑. All rights reserved.
//

import SpriteKit
import SwiftyJSON

// params の形式は守る必要が有る
// TODO: 各イベントにコールバックをもたせて，同期的に連続で実行できるようにする
class GameSceneEvent: NSObject {
    typealias eventID = String
    
    static let TALK: eventID        = "talk"
    static let BTN_PUSHED: eventID  = "ready_action"
    static let PLAYER_MOVE: eventID = "player_move"
    static let END_OF_TALK: eventID = "wait_for_touch"
    
    static var events: Dictionary<eventID, (JSON?) -> EventListener<Any>> =
    [
        TALK : {
            params in
            return EventListener<Any>() {
                sender, args in
                let controller = sender as! GameViewController
                let skView     = controller.view as! SKView
                let scene      = skView.scene as! GameScene
                let map        = scene.map
                let sheet      = map.getSheet()
                
                // params の validation
                let talker: String
                let talkBody: String
                let talkSide: Dialog.TALK_SIDE
                if  let json      = params,
                    let _character = json["talker"].string,
                    let _body      = json["talk_body"].string,
                    let _talk_side = json["talk_side"].string,
                    let _talker    = TALKER_IMAGE[_character]
                {
                    talker = _talker
                    talkBody = _body
                    switch _talk_side {
                    case "L": talkSide = Dialog.TALK_SIDE.left
                    case "R": talkSide = Dialog.TALK_SIDE.right
                    default: print("Invalid json param for talking"); return
                    }
                } else {
                    print("Invalid json param for talking")
                    return
                }
                
                scene.actionButton_.hidden = true
                
                if let playerTuple = map.getObjectByName(objectNameTable.PLAYER_NAME) {
                    let player = playerTuple.object
                    let playerPosition = TileCoordinate.getSheetCoordinateFromScreenCoordinate(
                        sheet!.getSheetPosition(),
                        screenCoordinate: player.getRealTimePosition())
                    
                    // キャラクターとかぶらないように，テキストボックスの位置を調整
                    var DialogPosition: Dialog.POSITION
                    if playerPosition.y <= scene.frame.height / 2 {
                        DialogPosition = Dialog.POSITION.top
                    } else {
                        DialogPosition = Dialog.POSITION.bottom
                    }
                    scene.textBox_.show(DialogPosition)
                    
                    // テキスト描画
                    scene.textBox_.drawText(talker, body: talkBody, side: talkSide)
                    
                    controller.touchEvent.remove(controller.movePlayer_)
                    controller.touchEvent.add(GameSceneEvent.events[END_OF_TALK]!(nil))
                }
            }
        },
        
        END_OF_TALK : {
            params in
            return EventListener<Any>() {
                sender, args in
                let controller = sender as! GameViewController
                let skView     = controller.view as! SKView
                let scene      = skView.scene as! GameScene
                let map        = scene.map
                scene.textBox_.hide()
                
                controller.touchEvent.remove(GameSceneEvent.events[END_OF_TALK]!(nil))
                controller.touchEvent.add(controller.movePlayer_)
            }
        },
        
        BTN_PUSHED : {
            params in
            return EventListener<Any>() {
                sender, args in
                let controller = sender as! GameViewController
                let skView     = controller.view as! SKView
                let scene      = skView.scene as! GameScene
                let map        = scene.map
                
                scene.actionButton_.hidden = false
                
                // TODO : params によって挙動を分ける
                let talkInfo = JSON(
                    [
                        "talker" : "player",
                        "talk_body" : "・・・・・・。",
                        "talk_side" : "L"
                    ]
                )
                controller.actionEvent.add(GameSceneEvent.events[TALK]!(talkInfo))
            }
        },
        
        PLAYER_MOVE : {
            params in
            return EventListener<Any>() {
                sender, args in
                let controller = sender as! GameViewController
                let skView     = controller.view as! SKView
                let scene      = skView.scene as! GameScene
                let map        = scene.map
                let sheet      = map.getSheet()!
                let touchedPoint: CGPoint = args as! CGPoint
                scene.textBox_.hide()
                scene.actionButton_.hidden = true
                
                // フレーム上をタッチしていたら無視する
                if sheet.isOnFrame(touchedPoint) { return }
                
                // route search
                let player: Object
                let playerCoordinate: TileCoordinate
                (playerCoordinate, player) = map.getObjectByName(objectNameTable.PLAYER_NAME)!
                let departure =
                    TileCoordinate.getTileCoordinateFromSheetCoordinate(player.getPosition())
                let destination =
                    TileCoordinate.getTileCoordinateFromScreenCoordinate(sheet.getSheetPosition(), screenCoordinate: args as! CGPoint)
                let aStar = AStar(map: map)
                aStar.initialize(departure, destination: destination)
                
                var events: [EventDispatcher<Any>] = []
                if let path = aStar.main() {
                    var actions: Array<SKAction> = []
                    for step: TileCoordinate in path {
                        let stepPoint: CGPoint = TileCoordinate.getSheetCoordinateFromTileCoordinate(step)
                        actions += player.getActionTo(stepPoint)
                        
                        // イベントが存在したら動きを止める
                        let eventsOnStep = map.getEventsOn(step)
                        if eventsOnStep.count > 0 {
                            events = eventsOnStep
                            break
                        }
                    }
                    
                    // オブジェクトを動かす
                    // TODO : イベントの種類をここで渡す
                    player.runAction(
                        actions,
                        callback:
                        {
                            for event in events {
                                event.trigger(controller, args: nil)
                        }
                    })
                    
                    // TODO : 位置情報をリアルタイムに更新する
                    /*let maxTime = CGFloat(actions.count) * player.getMovingSpeed()
                    let updateInterval = player.getMovingSpeed()/2
                    for (var delay: CGFloat=0.0; delay<maxTime; delay+=updateInterval) {
                        dispatch_after(
                            dispatch_time(DISPATCH_TIME_NOW, Int64(delay * 1000)),
                            dispatch_get_main_queue(),
                            { map.updateObjectPlacement(sheet.getSheetPosition(), object: player) })
                    }*/
                    
                    if let scrollAction = sheet.scrollSheet(destination) {
                        let delay = SKAction.waitForDuration(
                            NSTimeInterval(Double(player.getMovingSpeed() * CGFloat(path.count))))
                        var actions: Array<SKAction> = []
                        actions.append(delay)
                        actions.append(scrollAction)
                        UIApplication.sharedApplication().beginIgnoringInteractionEvents()
                        sheet.runAction(actions, callback: {
                            
                            UIApplication.sharedApplication().endIgnoringInteractionEvents()
                            
                            // 位置情報更新
                            map.updateObjectPlacement(player)
                        })
                    }
                }
            }
        }
    ]
}
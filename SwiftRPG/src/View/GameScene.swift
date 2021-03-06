//
//  GameScene.swift
//  SwiftRPG
//
//  Created by 兎澤佑 on 2015/06/27.
//  Copyright (c) 2015年 兎澤佑. All rights reserved.
//

import SpriteKit
import PromiseKit
import Foundation

/// view controller に処理を delegate する
protocol GameSceneDelegate: class {
    func frameTouched(_ location: CGPoint)
    func gameSceneTouched(_ location: CGPoint)
    func actionButtonTouched()
    func menuButtonTouched()
    func viewUpdated()
    func addEvent(_ events: [EventListener])
}

/// ゲーム画面
class GameScene: Scene, GameSceneProtocol {
    var gameSceneDelegate: GameSceneDelegate?
    @IBAction func didPressMenuButton(_ sender: AnyObject) {
        self.gameSceneDelegate?.menuButtonTouched()
    }

    // MARK: GameSceneProtocol Properties

    @IBOutlet weak var actionButton: UIButton!
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var eventDialog: DialogLabel!
    var map: Map?
    var textBox: Dialog!

    // MARK: ---
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if map == nil { return }
        let location = touches.first!.location(in: self)
        if self.map!.sheet!.isOnFrame(location) {
            self.gameSceneDelegate?.frameTouched(location)
        } else {
            self.gameSceneDelegate?.gameSceneTouched(location)
        }
    }

    func actionButtonTouched(_ sender: UIButton) {
        self.gameSceneDelegate?.actionButtonTouched()
    }

    override func update(_ currentTime: TimeInterval) {
        map?.updateObjectsZPosition()
        self.gameSceneDelegate?.viewUpdated()
    }

    // MARK: GameSceneProtocol Methods

    func movePlayer(_ playerActions: [SKAction], destination: CGPoint, events: [EventListener], screenActions: [SKAction]) {
        self.textBox.hide()
        self.actionButton.isHidden = true

        let player = self.map?.getObjectByName(objectNameTable.PLAYER_NAME)!
        player?.runAction(playerActions, destination: destination, callback: {
            self.gameSceneDelegate?.addEvent(events)
        })

        if screenActions.isEmpty { return }
        UIApplication.shared.beginIgnoringInteractionEvents()
        self.map?.sheet!.runAction(screenActions, callback: {
            UIApplication.shared.endIgnoringInteractionEvents()
            self.map?.updateObjectPlacement(player!)
        })
    }

    func hideAllButtons() -> Promise<Void> {
        return Promise { fulfill, reject in
            UIView.animate(withDuration: 0.2, animations: {
                self.menuButton.alpha = 0
                self.eventDialog.alpha = 0
                self.actionButton.alpha = 0
                self.textBox.hide()
            }, completion: {
                _ in
                self.menuButton.isHidden = true
                self.eventDialog.isHidden = true
                self.actionButton.isHidden = true
                self.menuButton.alpha = 1
                self.eventDialog.alpha = 1
                self.actionButton.alpha = 1
                fulfill()
            })
        }
    }

    func showDefaultButtons() -> Promise<Void> {
        self.menuButton.alpha = 0

        return Promise { fulfill, reject in
            UIView.animate(
                withDuration: 0.2,
                delay: 0.0,
                options: [.curveLinear],
                animations: { () -> Void in
                    self.menuButton.isHidden = false
                    self.menuButton.alpha = 1
                }
            ) { (animationCompleted: Bool) -> Void in fulfill()}
        }
    }

    // MARK: ---
}


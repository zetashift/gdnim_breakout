import gdnim
import godotapi / [kinematic_body_2d, viewport,
                   packed_scene, input_event_mouse_button,
                   resource_loader, scene_tree]

gdobj Paddle of KinematicBody2D:
  var ballScene: PackedScene

  method enter_tree() =
    discard register(paddle)

  proc hot_unload(): seq[byte] {.gdExport.} =
    self.queue_free()

  method physicsProcess*(d: float) =
    let
      mouseX = self.getViewport().getMousePosition().x
      y = self.position.y

    self.position = vec2(mouseX, y)

  method input*(ev: InputEvent) =
    if ev of InputEventMouseButton and ev.isPressed():
      let ball = self.ballScene.instance() as RigidBody2D
      ball.position = self.position + vec2(0.0, -16.0)
      self.getTree().root.addChild(ball)

  method ready*() =
    self.ballScene = load("res://scenes/Ball.tscn") as PackedScene
    self.setProcessInput(true)
    self.setPhysicsProcess(true)

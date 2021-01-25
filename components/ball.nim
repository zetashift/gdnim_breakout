import godot
import godotapi / [node, rigid_body_2d]
import hot

gdobj Ball of RigidBody2D:
  var speedUp {.gdExport.} = 50
  var maxSpeed = 300

  method enter_tree() =
    discard register(ball)

  proc hot_unload():seq[byte] {.gdExport.} =
    self.queue_free()

  method physicsProcess*(delta: float) =
    let bodies = self.getCollidingBodies()

    # This is still a Variant so we have to convert it
    for bodyVariant in bodies:
      let body = asObject[Node2D](bodyVariant)
      if body.isInGroup("Bricks"):
        body.queueFree()

      if body.name == "Paddle":
        let
          speed = self.linearVelocity.length
          anchor = body.getNode("Anchor").as(Position2D)
          direction = self.position - body.globalPosition
          velocity = direction.normalized * min(speed+self.speedUp, self.maxSpeed)

        self.linearVelocity = velocity

    # Check if ball is outside of bounds
    let bound = self.getViewportRect().size + self.getViewportRect().position
    if self.position.y > bound.y:
      self.queueFree()

  method ready*() = self.setPhysicsProcess(true)

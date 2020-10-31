import godot
import godotapi/[sprite, scene_tree, packed_scene, resource_loader, node_2d]
import hot
import tables
import strformat

gdobj Gun of Sprite:

  var compName = "gun"
  var bulletResPath = "res://bullet.tscn"
  var bulletRes:PackedScene

  var button_fireSingle:Node
  var bulletSpawnPoint:Node2D

  var bulletId:int
  var bullets:Table[string, Node]

  method enter_tree() =
    var button_fireSingle = self.get_parent().get_node("Button_FireSingle")
    self.button_fireSingle = button_fireSingle
    discard button_fireSingle.connect("pressed", self, "fire_single")

    self.bulletSpawnPoint = self.get_node("BulletSpawnPoint") as Node2D
    register(gun)?.load(self.bulletId, self.position)
    self.setupBullets()

  method exit_tree() =
    self.bulletRes = nil

  proc reload():seq[byte] {.gdExport.} =
    self.queue_free()
    save(self.bulletId, self.position)

  proc setupBullets(bulletData:seq[byte] = @[]) {.gdExport.} =
    print "gun: setupBullets"
    self.bulletRes = resource_loader.load(self.bulletResPath) as PackedScene

    var pathv = $self.get_path()
    withSome register(bullet, pathv, pathv, save_bullets, setup_bullets):
      some bb:
        var count:int
        bb.unpack(count)
        if count == 0: return
        print &"gun: got {count} bullets"
        for i in 0..<count:
          var bdata:seq[byte]
          bb.unpack(bdata)
          var bullet = self.bulletRes.instance()
          var vid = bullet.call("unpack_data", bdata.toVariant)
          var bid = vid.asString
          print &"gun: reload bullet {bid}"
          discard bullet.connect("dead", self, "bullet_dead")
          self.get_tree().root.add_child(bullet)
          self.bullets[bid] = bullet

  proc saveBullets():seq[byte] {.gdExport.} =
    print "gun: bullet reload return saveData"
    #destroy any existing bullets
    var bullets = self.bullets
    var ms = MsgStream.init()
    ms.pack(bullets.len)
    for id, b in bullets:
      b.disconnect("dead", self, "bullet_dead")
      var bv = b.call("pack_data")
      var bdata:seq[byte]
      discard fromVariant(bdata, bv)
      ms.pack(bdata)
      self.bullet_dead(id)
    self.bulletRes = nil

    result = cast[seq[byte]](ms.data)


  proc createBullet(v:Vector2, p:Vector2) =
    var b = self.bulletRes.instance()
    var id = self.bulletId
    inc self.bulletId
    b.call_deferred("set_data", ($id).toVariant, v.toVariant, p.toVariant)
    discard b.connect("dead", self, "bullet_dead")
    self.get_tree().root.add_child(b)
    self.bullets[$id] = b

  proc bullet_dead(id:string) {.gdExport.} =
    if self.bullets.hasKey(id):
      print &"gun: dead bullet {id}"
      var b = self.bullets[id]
      b.queue_free()
      self.bullets.del(id)

  proc fireSingle() {.gdExport.} =
    self.createBullet(vec2(1.2,0.0), self.bulletSpawnPoint.global_position)
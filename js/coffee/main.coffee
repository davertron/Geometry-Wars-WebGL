SCREEN_WIDTH = window.innerWidth
SCREEN_HEIGHT = window.innerHeight

COLOR = 0x97a8ba

container = null
stats = null
camera = null
glowcamera = null
target = null
scene = null
glowscene = null
renderer = null
renderTarget = null
renderTargetGlow = null
renderTargetParameters =
    minFilter: THREE.LinearFilter
    magFilter: THREE.LinearFilter
    format: THREE.RGBFormat
    stencilBuffer: false

boxes = []

spaceship = null
score = 0
multiplier = 1

godMode = false

enemies = []

particles = []

grid = null
hexGrid = null
background = null

lastTick = (new Date()).getTime()

pointLight = null

finalcomposer = null
finalshader = null
glowcomposer = null
hblur = null
vblur = null

paused = false
inMenu = true
mainMenu = true

windowHalfX = window.innerWidth / 2
windowHalfY = window.innerHeight / 2

WORLD_BOUNDS =
    minX: -500
    maxX: 500
    minY: -500
    maxY: 500

# Places the enemy can spawn from
SPAWN_POINTS = [
    new THREE.Vector3 -300, -300, 0
    new THREE.Vector3 -300, 300, 0
    new THREE.Vector3 300, -300, 0
    new THREE.Vector3 300, 300, 0
]

finalshader =
    uniforms:
        tDiffuse:
            type: "t"
            value: 0
            texture: null
        tGlow:
            type: "t"
            value: 1
            texture: null
        tGreyscale:
            type: "t"
            value: 0
            texture: null
    vertexShader:
        "varying vec2 vUv;

        void main() {

            vUv = vec2( uv.x, 1.0 - uv.y );
            gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );

        }"
    fragmentShader:
        "uniform sampler2D tDiffuse;
        uniform sampler2D tGlow;
        uniform bool tGreyscale;

        varying vec2 vUv;

        void main() {
            vec4 texel = texture2D( tDiffuse, vUv );
            vec4 glow = texture2D( tGlow, vUv );
            if(tGreyscale){
                gl_FragColor = texel + vec4(0.5, 0.75, 1.0, 1.0) * glow * 4.0;
                float gray = dot(gl_FragColor.rgb, vec3(0.299, 0.587, 0.114));
                gl_FragColor = vec4(gray, gray, gray, gl_FragColor.a);
            } else {
                gl_FragColor = texel + vec4(0.5, 0.75, 1.0, 1.0) * glow * 4.0;
            }
        }"

MAIN_MENU_COLORS = [
    0xF84444,
    0x66B002,
    0xD586F5,
    0x67E5E8,
    0xF7FF00
]

textures =
    galaxy:
        url: '/img/galaxy.jpg'
        material: null

rotateVector = (vector, axis, rotation) ->
    matrix = new THREE.Matrix4().makeRotationAxis( axis, rotation )

    matrix.multiplyVector3 vector

class Box
    constructor: (@position=new THREE.Vector3(0,0,0), @size=5, @color=0xffffff, @opacity=1.0) ->
        geometry = new THREE.Geometry()
        negSize = -1 * @size

        geometry.vertices.push(
            new THREE.Vector3( negSize, negSize, 0 ),
            new THREE.Vector3( size, negSize, 0 ),
            new THREE.Vector3( size, size, 0 ),
            new THREE.Vector3( negSize, size, 0 ),
            new THREE.Vector3( negSize, negSize, 0 )
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: 3}) )

        @mesh.position = position
        @glowMesh.position = position
    getMesh: ->
        @mesh
    getGlowMesh: ->
        @glowMesh

class Trail
    constructor: ->
        @meshes = []
        @glowMeshes = []

    grow: (position, scene, glowscene) ->
        plane = new THREE.PlaneGeometry(3, 3)
        newMesh = new THREE.Mesh(plane, new THREE.MeshBasicMaterial ( { color: 0xCC33FF, opacity: 0.5 }))
        glowMesh = new THREE.Mesh(plane, new THREE.MeshBasicMaterial ( { color: 0xCC33FF, opacity: 0.5 }))

        newMesh.position = position.clone()
        newMesh.age = 0
        @meshes.push(newMesh)
        scene.add(newMesh)

        glowMesh.position = position.clone()
        @glowMeshes.push(glowMesh)
        glowscene.add(glowMesh)

    update: (scene, glowscene) ->
        keepMeshes = []
        keepGlowMeshes = []

        # Get rid of old trail pieces
        for mesh, i in @meshes
            mesh.age += 1
            if(mesh.age < 50)
                mesh.scale.x *= 0.98
                mesh.scale.y *= 0.98
                @glowMeshes[i].scale.x *= 0.98
                @glowMeshes[i].scale.y *= 0.98
                keepMeshes.push(mesh)
                keepGlowMeshes.push(@glowMeshes[i])
            else
                scene.remove mesh
                glowscene.remove @glowMeshes[i]

        @meshes = keepMeshes
        @glowMeshes = keepGlowMeshes

class Bullet
    constructor: (position, @velocity) ->
        @position = position.clone()
        @dead = false
        @lastUpdate = (new Date()).getTime()
        @collideRadius = 5

        geometry = new THREE.Geometry()
        vertex = @velocity.clone().normalize()

        geometry.vertices.push(
            vertex,
            vertex.clone().multiplyScalar 10
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: 0xFA3C23, opacity: 1.0, linewidth: 5}) )
        @mesh.position = @position
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: 0xFA3C23, opacity: 1.0, linewidth: 5}) )
        @glowMesh.position = @position

    update: ->
        now = (new Date()).getTime()
        scaledVelocity = @velocity.clone().multiplyScalar((now - @lastUpdate) / 1000)

        @lastUpdate = now

        if(!paused and !@dead)
            @mesh.position = @position.addSelf(scaledVelocity)
            @glowMesh.position = @position.addSelf(scaledVelocity)

            if(@position.x > WORLD_BOUNDS.maxX or @position.x < WORLD_BOUNDS.minX or @position.y > WORLD_BOUNDS.maxY or @position.y < WORLD_BOUNDS.minY)
                @die(scene, glowscene)

    die: (scene, glowscene) ->
        @dead = true
        scene.remove @mesh
        glowscene.remove @glowMesh

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    collide: (other) ->
        if !@dead and !other.dead and @position.clone().subSelf(other.position).length() <= (other.collideRadius + @collideRadius)
            @die scene, glowscene
            other.die scene, glowscene

updateScore = (entity) ->
    score += multiplier * entity.value
    if score % 100000 == 0
        spaceship.lives += 1
        $('#lives').html('Lives: ' + spaceship.lives)
    $('#score').html('Score: ' + score)

class Shield
    constructor: (position) ->
        geometry = new THREE.Geometry()
        @position = position or new THREE.Vector3 0, 0, 0
        color = 0xffffff
        opacity = 1.0
        angleIncrement = (2*Math.PI)/8
        radius = 15

        # Hexagon...
        geometry.vertices.push(
            new THREE.Vector3(radius, 0, 0),
            new THREE.Vector3(radius*Math.cos(angleIncrement), radius*Math.sin(angleIncrement), 0),
            new THREE.Vector3(radius*Math.cos(2*angleIncrement), radius*Math.sin(2*angleIncrement), 0),
            new THREE.Vector3(radius*Math.cos(3*angleIncrement), radius*Math.sin(3*angleIncrement), 0),
            new THREE.Vector3(radius*Math.cos(4*angleIncrement), radius*Math.sin(4*angleIncrement), 0),
            new THREE.Vector3(radius*Math.cos(5*angleIncrement), radius*Math.sin(5*angleIncrement), 0),
            new THREE.Vector3(radius*Math.cos(6*angleIncrement), radius*Math.sin(6*angleIncrement), 0),
            new THREE.Vector3(radius*Math.cos(7*angleIncrement), radius*Math.sin(7*angleIncrement), 0),
            new THREE.Vector3(radius, 0, 0)
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: color, opacity: opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: color, opacity: opacity, linewidth: 3}) )
        @mesh.position = position
        @glowMesh.position = position

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    die: (scene, glowscene) ->
        scene.remove @mesh
        glowscene.remove @glowMesh

class Spaceship
    constructor: (position) ->
        geometry = new THREE.Geometry()
        trailGeometry = new THREE.Geometry()
        color = color or 0xffffff
        opacity = opacity or 1.0
        heading = new THREE.Vector3(0, 1, 0)

        @heading = heading
        if position
            @position = position.clone()
        else
            @position = new THREE.Vector3 0, 0, 0
        @velocity = 0
        @rotation = 0
        @trail = new Trail()
        @bullets = []
        @shooting = false
        @lastShotTime
        @lastUpdate = (new Date()).getTime()
        @lives = 3
        @type = 'Spaceship'
        @collideRadius = 3
        @invincible = true
        @spawnTime = (new Date()).getTime()
        @shield = new Shield(@position.clone())

        geometry.vertices.push(
            new THREE.Vector3(0, -3, 0),
            new THREE.Vector3(-3, 0, 0),
            new THREE.Vector3(-2, 2, 0),
            new THREE.Vector3(-3, 0, 0),
            new THREE.Vector3(0, -1, 0),
            new THREE.Vector3(3, 0, 0),
            new THREE.Vector3(0, -3, 0),
            new THREE.Vector3(3, 0, 0),
            new THREE.Vector3(2, 2, 0)
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: color, opacity: opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: color, opacity: opacity, linewidth: 3}) )
        @mesh.position = @position
        @glowMesh.position = @position
        @mesh.scale.x *= 3
        @mesh.scale.y *= 3
        @glowMesh.scale.x *= 3
        @glowMesh.scale.y *= 3

    reset: () ->
        @heading = new THREE.Vector3(0, 1, 0)
        @position = new THREE.Vector3(0, 0, 0)
        @mesh.position = @position
        @glowMesh.position = @position
        @mesh.rotation.z = 0
        @glowMesh.rotation.z = 0
        @velocity = 0
        @rotation = 0
        @bullets = []
        @shooting = false
        @lastShotTime = null
        @lastUpdate = (new Date()).getTime()
        @lives = 3
        @invincible = true
        @spawnTime = (new Date()).getTime()
        @shield = new Shield(@position.clone())
        @shield.spawn(scene, glowscene)

    spawn: (scene, glowscene) ->
        @spawnTime = (new Date()).getTime()
        @shield.spawn(scene, glowscene)
        scene.add( @mesh )
        glowscene.add( @glowMesh )

    die: (scene, glowscene) ->
        @lives -= 1
        if @lives >= 0
            $('#lives').html('Lives: ' + @lives)

        if @lives > 0
            @position = new THREE.Vector3(0, 0, 0)
            @mesh.position = @position.clone()
            @glowMesh.position = @position.clone()
            @invincible = true
            @spawnTime = (new Date()).getTime()
            @shield = new Shield(@position.clone())
            @shield.spawn(scene, glowscene)

            for enemy in enemies
                enemy.die scene, glowscene, false, false

            for bullet in @bullets
                bullet.die scene, glowscene

            explosion @position, @color, 1.0, 20, particles
            multiplier = 1
        else
            setGameOver()

    update: (scene, glowscene, bounds) ->
        now
        timeScalar
        scaledRotation
        scaledVelocity
        bullet

        for enemy in enemies
            @collide enemy

        now = (new Date()).getTime()
        timeScalar = (now - @lastUpdate) / 1000

        if @rotation != 0 and !paused
            # Rotate the spaceship
            scaledRotation = @rotation * timeScalar
            rotateVector(@heading, new THREE.Vector3( 0, 0, 1 ), scaledRotation)

            @mesh.rotation.z += scaledRotation
            @glowMesh.rotation.z += scaledRotation

        scaledVelocity =  timeScalar * @velocity

        if not paused
            @trail.update scene, glowscene
            if now - @spawnTime > 3000 and @shield
                @shield.die scene, glowscene
                @shield = null
                @invincible = false

        # Move the spaceship
        if @velocity != 0 and not paused
            @position = @position.addSelf(@heading.clone().multiplyScalar(scaledVelocity))

            # Update mesh positions
            @mesh.position = @position
            @glowMesh.position = @position

            # Update shield position
            if @shield
                @shield.mesh.position = @position.clone()
                @shield.glowMesh.position = @position.clone()

            # Add vertices to the trail
            @trail.grow(@position.clone().subSelf(@heading.clone().normalize().multiplyScalar(5)), scene, glowscene)

            # Don't let the spaceship go out of bounds
            if @position.x > bounds.maxX
                @position.x = bounds.maxX
            else if @position.x < bounds.minX
                @position.x = bounds.minX

            if @position.y > bounds.maxY
                @position.y = bounds.maxY
            else if @position.y < bounds.minY
                @position.y = bounds.minY

        if @shooting and (not @lastShotTime or (now - @lastShotTime > 100)) and not paused
            bullet = new Bullet(@position.clone(), @heading.clone().normalize().multiplyScalar(600))
            bullet.spawn scene, glowscene
            replaceDead bullet, @bullets
            @lastShotTime = now

        for bullet in @bullets
            bullet.update()

        @lastUpdate = now

    collide: (other) ->
        if not @dead and not other.dead and @position.clone().subSelf(other.position).length() <= (other.collideRadius + @collideRadius)
            if not godMode and not @invincible
                @die scene, glowscene
            other.die scene, glowscene, false


# Don't keep creating new arrays, just replace dead items in your current
# array
replaceDead = (entity, array) ->
    spliced = false

    for object, i in array
        if object.dead
            array.splice i, 1, entity
            spliced = true
            break

    if not spliced
        array.push entity

class DiamondEnemy
    constructor: (position, color, opacity) ->
        geometry = new THREE.Geometry()
        opacity = opacity or 1.0

        if position
            @position = position.clone()
        else
            @position = new THREE.Vector3 0, 0, 0
        @velocity = spaceship.position.clone().subSelf(@position).normalize().multiplyScalar(50)
        @lastUpdate = (new Date()).getTime()
        @collideRadius = 10
        @type = 'DiamondEnemy'
        @value = 50
        @color = color or 0x14CEFC

        geometry.vertices.push(
            new THREE.Vector3( -8, 0, 0 ),
            new THREE.Vector3( 0, 10, 0 ),
            new THREE.Vector3( 8, 0, 0 ),
            new THREE.Vector3( 0, -10, 0 ),
            new THREE.Vector3( -8, 0, 0 )
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )

        @mesh.position = @position
        @glowMesh.position = @position

    update: (scene, glowscene, bounds) ->
        now = (new Date()).getTime()
        velocityLength = @velocity.length()
        scaledVelocity = @velocity.clone().multiplyScalar((now - @lastUpdate) / 1000)

        if not paused and not @dead
            # Slowly track the spaceship
            if Math.random() < 0.1
                @velocity = spaceship.position.clone().subSelf(@position).normalize().multiplyScalar(50)
                scaledVelocity = @velocity.clone().multiplyScalar((now - @lastUpdate) / 1000)

            @mesh.position = @position.addSelf scaledVelocity
            @glowMesh.position = @position.addSelf scaledVelocity

            if @position.x > WORLD_BOUNDS.maxX or @position.x < WORLD_BOUNDS.minX
                @velocity.x *= -1

            if @position.y > WORLD_BOUNDS.maxY or @position.y < WORLD_BOUNDS.minY
                @velocity.y *= -1

        @lastUpdate = now

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    die: (scene, glowscene, shouldUpdateScore=true) ->
        @dead = true
        scene.remove @mesh
        glowscene.remove @glowMesh
        explosion @position, @color, 1.0, 20, particles
        if shouldUpdateScore
            updateScore this

class PinWheelEnemy
    constructor: (position, color, opacity) ->
        geometry = new THREE.Geometry()
        opacity = opacity or 1.0

        if position
            @position = position.clone()
        else
            @position = new THREE.Vector3 0, 0, 0
        @velocity = new THREE.Vector3(Math.random()*50, Math.random()*50, 0).normalize().multiplyScalar(25)
        @lastUpdate = (new Date()).getTime()
        @collideRadius = 10
        @rotation = 0.5
        @type = 'PinWheelEnemy'
        @value = 25
        @color = color or 0xCB49FF

        geometry.vertices.push(
            new THREE.Vector3( 0, 0, 0 ),
            new THREE.Vector3( 0, 8, 0 ),
            new THREE.Vector3( -8, 8, 0 ),
            new THREE.Vector3( 0, 0, 0 ),
            new THREE.Vector3( -8, 0, 0 ),
            new THREE.Vector3( -8, -8, 0 ),
            new THREE.Vector3( 0, 0, 0 ),
            new THREE.Vector3( 0, -8, 0 ),
            new THREE.Vector3( 8, -8, 0 ),
            new THREE.Vector3( 0, 0, 0 ),
            new THREE.Vector3( 8, 0, 0 ),
            new THREE.Vector3( 8, 8, 0 ),
            new THREE.Vector3( 0, 0, 0 )
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )

        @mesh.position = @position
        @glowMesh.position = @position

    update: (scene, glowscene, bounds) ->
        now = (new Date()).getTime()
        timeScalar = (now - @lastUpdate) / 1000
        scaledVelocity = @velocity.clone().multiplyScalar(timeScalar)
        scaledRotation = @rotation * timeScalar

        if not paused and not @dead
            # Randomly rotate the velocity vector around slowly
            if Math.random() < 0.1
                rotateVector(@velocity, new THREE.Vector3(0, 0, 1), Math.sin(now*Math.random())*0.25)

            @mesh.position = @position.addSelf scaledVelocity
            @glowMesh.position = @position.addSelf scaledVelocity

            @mesh.rotation.z += scaledRotation
            @glowMesh.rotation.z += scaledRotation

            if @position.x > WORLD_BOUNDS.maxX or @position.x < WORLD_BOUNDS.minX
                @velocity.x *= -1

            if @position.y > WORLD_BOUNDS.maxY or @position.y < WORLD_BOUNDS.minY
                @velocity.y *= -1

        @lastUpdate = now

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    die: (scene, glowscene, shouldUpdateScore=true) ->
        @dead = true
        scene.remove @mesh
        glowscene.remove @glowMesh
        explosion @position, @color, 1.0, 20, particles
        if shouldUpdateScore
            updateScore this

class CrossBoxEnemy
    constructor: (position, color, opacity) ->
        geometry = new THREE.Geometry()
        opacity = opacity or 1.0

        if position
            @position = position.clone()
        else
            @position = new THREE.Vector3 0, 0, 0
        @velocity = new THREE.Vector3(Math.random()*50, Math.random()*50, 0).normalize().multiplyScalar(50)
        @lastUpdate = (new Date()).getTime()
        @collideRadius = 10
        @rotation = 0.5
        @type = 'CrossBoxEnemy'
        @value = 75
        @color = color or 0xFF4AD5

        geometry.vertices.push(
            new THREE.Vector3( -8, 8, 0 ),
            new THREE.Vector3( 8, 8, 0 ),
            new THREE.Vector3( -8, -8, 0 ),
            new THREE.Vector3( -8, 8, 0 ),
            new THREE.Vector3( 8, -8, 0 ),
            new THREE.Vector3( -8, -8, 0 ),
            new THREE.Vector3( 8, 8, 0 ),
            new THREE.Vector3( 8, -8, 0 )
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )

        @mesh.position = @position
        @glowMesh.position = @position

    update: (scene, glowscene, bounds) ->
        now = (new Date()).getTime()
        timeScalar = (now - @lastUpdate) / 1000
        scaledVelocity = @velocity.clone().multiplyScalar(timeScalar)

        if not paused and not @dead
            # Slowly track the spaceship
            if Math.random() < 0.1
                @velocity = spaceship.position.clone().subSelf(@position).normalize().multiplyScalar(50)
                scaledVelocity = @velocity.clone().multiplyScalar((now - @lastUpdate) / 1000)

            @mesh.position = @position.addSelf scaledVelocity
            @glowMesh.position = @position.addSelf scaledVelocity

            if @position.x > WORLD_BOUNDS.maxX or @position.x < WORLD_BOUNDS.minX
                @velocity.x *= -1

            if @position.y > WORLD_BOUNDS.maxY or @position.y < WORLD_BOUNDS.minY
                @velocity.y *= -1

        @lastUpdate = now

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    die: (scene, glowscene, shouldUpdateScore=true, shouldSpawnBabies=true) ->
        @dead = true
        scene.remove @mesh
        glowscene.remove @glowMesh
        explosion @position, @color, 1.0, 20, particles
        if shouldUpdateScore
            updateScore this

        # Whenever a crossbox dies it spawns more smaller little fuckers,
        # unless the player just died
        if shouldSpawnBabies
            for i in [0..2]
                baby = new BabyCrossBoxEnemy(this.position.clone().addSelf(new THREE.Vector3(Math.random()*20, Math.random()*20, 0)), this.color, this.opacity)
                replaceDead baby, enemies
                baby.spawn scene, glowscene

class BabyCrossBoxEnemy
    constructor: (position, color, opacity) ->
        geometry = new THREE.Geometry()
        opacity = opacity or 1.0

        if position
            @position = position.clone()
        else
            @position = new THREE.Vector3 0, 0, 0
        @velocity = new THREE.Vector3(Math.random(), Math.random(), 0).normalize().multiplyScalar(50)
        @lastUpdate = (new Date()).getTime()
        @collideRadius = 10
        @type = 'BabyCrossBoxEnemy'
        @value = 25
        @color = color or 0xFF4AD5

        geometry.vertices.push(
            new THREE.Vector3( -8, 8, 0 ),
            new THREE.Vector3( 8, 8, 0 ),
            new THREE.Vector3( -8, -8, 0 ),
            new THREE.Vector3( -8, 8, 0 ),
            new THREE.Vector3( 8, -8, 0 ),
            new THREE.Vector3( -8, -8, 0 ),
            new THREE.Vector3( 8, 8, 0 ),
            new THREE.Vector3( 8, -8, 0 )
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: opacity, linewidth: 3}) )

        @mesh.position = @position
        @glowMesh.position = @position

        @mesh.scale.x *= 0.5
        @mesh.scale.y *= 0.5
        @glowMesh.scale.x *= 0.5
        @glowMesh.scale.y *= 0.5

    update: () ->
        now = (new Date()).getTime()
        timeScalar = (now - @lastUpdate) / 1000
        scaledVelocity = @velocity.clone().multiplyScalar(timeScalar)
        vectorTowardsSpaceship

        if not paused and not @dead
            # Rotate in a circle generally, but cheat towards the player
            rotateVector(@velocity, new THREE.Vector3(0, 0, 1), 0.1)
            vectorTowardsSpaceship = spaceship.position.clone().subSelf(@position)
            if Math.acos(@velocity.normalize().dot(vectorTowardsSpaceship.normalize())) < 1.5
                @velocity.normalize().multiplyScalar(100)
            else
                @velocity.normalize().multiplyScalar(50)

            @mesh.position = @position.addSelf scaledVelocity
            @glowMesh.position = @position.addSelf scaledVelocity

            if @position.x > WORLD_BOUNDS.maxX or @position.x < WORLD_BOUNDS.minX
                @velocity.x *= -1

            if @position.y > WORLD_BOUNDS.maxY or @position.y < WORLD_BOUNDS.minY
                @velocity.y *= -1

        @lastUpdate = now

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    die: (scene, glowscene, shouldUpdateScore=true) ->
        @dead = true
        scene.remove @mesh
        glowscene.remove @glowMesh
        explosion @position, @color, 1.0, 20, particles
        if shouldUpdateScore
            updateScore this

class Grid
    constructor: (@x, @y, @width, @height, @span, @color=0xffffff, @opacity=1.0, @linewidth=1) ->
        @meshes = []
        @glowMeshes = []

        numberOfXLines = width / span
        numberOfYLines = height / span
        minX = x
        maxX = minX + width
        minY = y
        maxY = minY + height
        geometry

        for currentX in [0..numberOfXLines]
            geometry = new THREE.Geometry()
            geometry.vertices.push(
                new THREE.Vector3(minX + (currentX * span), minY, 0),
                new THREE.Vector3(minX + (currentX * span), maxY, 0)
            )
            @meshes.push(
                new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: @linewidth}) )
            )
            @glowMeshes.push(
                new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: @linewidth}) )
            )

        for currentY in [0..numberOfYLines]
            geometry = new THREE.Geometry()
            geometry.vertices.push(
                new THREE.Vector3(minX, minY + (currentY * span), 0),
                new THREE.Vector3(maxX, minY + (currentY * span), 0)
            )
            @meshes.push(
                new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: color, opacity: opacity, linewidth: 1}) )
            )
            @glowMeshes.push(
                new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: color, opacity: opacity, linewidth: 1}) )
            )

    spawn: (scene, glowscene) ->
        for mesh in @meshes
            scene.add mesh

        for glowMesh in @glowMeshes
            glowscene.add glowMesh

# Draw a grid made up of hexagons
#
# @method HexGrid
# @param {Number} x x position of upper left-hand corner
# @param {Number} y y position of upper left-hand corner
# @param {Number} width
# @param {Number} height
# @param {Number} span The distance between hexagon center points
# @param {Number} [color=0xffffff] Hex value for color of grid
# @param {Number} [opacity=1.0] Value between 0.0 and 1.0 for alpha
class HexGrid
    constructor: (@x, @y, @width, @height, @span, @color=0xffffff, @opacity=1.0) ->

        @meshes = []
        @glowMeshes = []

        numberOfXHexagons = width / span
        numberOfYHexagons = height / span
        minX = x
        maxX = minX + width
        minY = y
        maxY = minY + height
        geometry
        halfSpan = @span / 2
        quarterSpan = halfSpan / 2
        threeQuarterSpan = halfSpan + quarterSpan
        X
        Y
        xOffset
        yOffset

        for currentXHex in [0..numberOfXHexagons]
            for currentYHex in [0..numberOfYHexagons]
                xOffset = (currentXHex * threeQuarterSpan) + minX
                yOffset = (currentYHex * span) + minY

                if currentXHex % 2 == 0
                    yOffset -= halfSpan

                geometry = new THREE.Geometry()
                geometry.vertices.push(
                    new THREE.Vector3(xOffset + quarterSpan, yOffset, 0),
                    new THREE.Vector3(xOffset + threeQuarterSpan, yOffset, 0),
                    new THREE.Vector3(xOffset + span, yOffset + halfSpan, 0),
                    new THREE.Vector3(xOffset + threeQuarterSpan, yOffset + span, 0),
                    new THREE.Vector3(xOffset + quarterSpan, yOffset + span, 0),
                    new THREE.Vector3(xOffset, yOffset + halfSpan, 0),
                    new THREE.Vector3(xOffset + quarterSpan, yOffset, 0)
                )

                @meshes.push(
                    new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: 3}) )
                )

                geometry = new THREE.Geometry()
                geometry.vertices.push(
                    new THREE.Vector3(xOffset + quarterSpan, yOffset, 0),
                    new THREE.Vector3(xOffset + threeQuarterSpan, yOffset, 0),
                    new THREE.Vector3(xOffset + span, yOffset + halfSpan, 0),
                    new THREE.Vector3(xOffset + threeQuarterSpan, yOffset + span, 0),
                    new THREE.Vector3(xOffset + quarterSpan, yOffset + span, 0),
                    new THREE.Vector3(xOffset, yOffset + halfSpan, 0),
                    new THREE.Vector3(xOffset + quarterSpan, yOffset, 0)
                )

                @glowMeshes.push(
                    new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: 3}) )
                )

    spawn: (scene, glowscene) ->
        for mesh in @meshes
            scene.add mesh

        for glowMesh in @glowMeshes
            glowscene.add glowMesh

class Particle
    constructor: (position, velocity, @maxAge=25, @color=0xFDA014, @opacity=1.0) ->
        geometry = new THREE.Geometry()

        @position = position or new THREE.Vector3(0, 0, 0)
        @velocity = velocity or new THREE.Vector3(0, 1, 0)
        @age = 0
        @lastUpdate = (new Date()).getTime()
        @dead = false

        geometry.vertices.push(
            new THREE.Vector3(0, 0, 0),
            velocity.clone().normalize().multiplyScalar(10)
        )

        @mesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: 2}) )
        @glowMesh = new THREE.Line( geometry, new THREE.LineBasicMaterial( { color: @color, opacity: @opacity, linewidth: 2}) )

        @mesh.position = @position
        @glowMesh.position = @position

    spawn: (scene, glowscene) ->
        scene.add @mesh
        glowscene.add @glowMesh

    die: (scene, glowscene) ->
        @dead = true
        scene.remove @mesh
        glowscene.remove @glowMesh

    update: () ->
        now = (new Date()).getTime()
        timeScalar
        ageScalar
        scaledVelocity

        @age += 1

        if @age >= @maxAge
            @die scene, glowscene

        if not paused and not @dead
            timeScalar = (now - @lastUpdate) / 1000
            ageScalar = (@maxAge - @age) / @maxAge
            #scaledVelocity = @velocity.clone().normalize().multiplyScalar(@maxAge - @age).multiplyScalar(timeScalar)
            scaledVelocity = @velocity.clone().multiplyScalar(timeScalar*ageScalar)

            @mesh.position = @position.addSelf scaledVelocity
            @glowMesh.position = @position.addSelf scaledVelocity

            if @position.x > WORLD_BOUNDS.maxX or @position.x < WORLD_BOUNDS.minX
                @velocity.x *= -1

            if @position.y > WORLD_BOUNDS.maxY or @position.y < WORLD_BOUNDS.minY
                @velocity.y *= -1

        @lastUpdate = now

explosion = (position, color, opacity=1.0, numberOfParticles, particles) ->
    angleIncrement = (2*Math.PI)/numberOfParticles
    x
    y
    p

    for i in [0..numberOfParticles]
        x = Math.cos(i * angleIncrement)
        y = Math.sin(i * angleIncrement)
        p = new Particle(position.clone(), (new THREE.Vector3(x, y, 0)).normalize().multiplyScalar(250), 50, color, opacity)
        replaceDead p, particles
        p.spawn scene, glowscene

window.unpause = () ->
    paused = false
    inMenu = false
    finalshader.uniforms[ 'tGreyscale' ].value = false
    initFinalComposer finalshader, scene, camera, renderer, renderTarget

    $('.menu').removeClass('current').hide()

window.pause = () ->
    $('.menu').removeClass('current').hide()
    paused = true
    inMenu = true
    finalshader.uniforms[ 'tGreyscale' ].value = true
    initFinalComposer finalshader, scene, camera, renderer, renderTarget

    $('#paused').addClass('current').find('.menu-actions li').removeClass('selected').first().addClass('selected').end().end().show()

setGameOver = () ->
    inMenu = true
    paused = true
    finalshader.uniforms[ 'tGreyscale' ].value = true
    initFinalComposer finalshader, scene, camera, renderer, renderTarget

    $('.menu').removeClass('current').hide()
    $('#game-over').addClass('current').find('.menu-actions li').removeClass('selected').first().addClass('selected').end().end().show()

window.start = () ->
    mainMenu = false
    inMenu = false
    unpause()
    $('.menu').removeClass('current').hide()
    buildGameScene()
    $('#hud').show()

window.goToMainMenu = () ->
    unpause()
    mainMenu = true
    inMenu = true
    $('.menu').removeClass('current').hide()
    buildMainMenuScene()
    $('#hud').hide()
    $('#main-menu').addClass('current').find('.menu-actions li').removeClass('selected').first().addClass('selected').end().end().show()

window.showControls = () ->
    $('.menu').removeClass('current').hide()
    $('#controls').addClass('current').find('.menu-actions li').removeClass('selected').first().addClass('selected').end().end().show()

window.restart = () ->
    for enemy in enemies
        enemy.die scene, glowscene, false

    for bullet in spaceship.bullets
        bullet.die scene, glowscene

    for particle in particles
        particle.die scene, glowscene

    spaceship.reset()
    enemies = []
    particles = []
    score = 0
    multiplier = 0
    $('#score').html('Score: ' + score)
    $('#lives').html('Lives: ' + spaceship.lives)
    paused = false
    finalshader.uniforms[ 'tGreyscale' ].value = false
    initFinalComposer finalshader, scene, camera, renderer, renderTarget
    $('.menu').hide()
    $('#game-over li').removeClass('selected').first().addClass('selected')

buildMainMenuScene = () ->
    # MAIN MENU SCENE
    camera = new THREE.PerspectiveCamera( 75, SCREEN_WIDTH / SCREEN_HEIGHT, 1, 100000 )
    camera.position.z = 50
    camera.position.y = 0
    cameraLight = new THREE.PointLight 0x666666
    camera.add cameraLight

    scene = new THREE.Scene()
    scene.add(new THREE.AmbientLight( 0xffffff ))
    pointLight = new THREE.PointLight COLOR
    pointLight.position.set 0, 100, 0
    scene.add pointLight

    # GLOW SCENE
    glowscene = new THREE.Scene()
    glowscene.add( new THREE.AmbientLight( 0xffffff ) )
    glowcamera = new THREE.PerspectiveCamera( 75, SCREEN_WIDTH / SCREEN_HEIGHT, 1, 100000 )
    glowcamera.position = camera.position

    # BUILD SCENE
    spaceship = new Spaceship()
    spaceship.spawn scene, glowscene

    # GLOW COMPOSER
    renderTargetGlow = new THREE.WebGLRenderTarget( SCREEN_WIDTH, SCREEN_HEIGHT, renderTargetParameters )

    hblur = new THREE.ShaderPass THREE.ShaderExtras[ "horizontalBlur" ]
    vblur = new THREE.ShaderPass THREE.ShaderExtras[ "verticalBlur" ]

    bluriness = 2

    hblur.uniforms[ 'h' ].value = bluriness / SCREEN_WIDTH
    vblur.uniforms[ 'v' ].value = bluriness / SCREEN_HEIGHT

    renderModelGlow = new THREE.RenderPass glowscene, glowcamera

    glowcomposer = new THREE.EffectComposer renderer, renderTargetGlow

    glowcomposer.addPass renderModelGlow
    glowcomposer.addPass hblur
    glowcomposer.addPass vblur

    # FINAL COMPOSER
    finalshader.uniforms[ 'tGlow' ].texture = glowcomposer.renderTarget2

    renderTarget = new THREE.WebGLRenderTarget( SCREEN_WIDTH, SCREEN_HEIGHT, renderTargetParameters )
    
    initFinalComposer finalshader, scene, camera, renderer, renderTarget, renderTargetParameters

buildGameScene = () ->
    # MAIN SCENE
    camera = new THREE.PerspectiveCamera 75, SCREEN_WIDTH / SCREEN_HEIGHT, 1, 100000
    camera.position.z = 280
    cameraLight = new THREE.PointLight 0x666666
    camera.add cameraLight

    scene = new THREE.Scene()
    scene.add( new THREE.AmbientLight( 0xffffff ) )
    pointLight = new THREE.PointLight COLOR
    pointLight.position.set 0, 100, 0
    scene.add pointLight

    # GLOW SCENE
    glowscene = new THREE.Scene()
    glowscene.add( new THREE.AmbientLight( 0xffffff ) )
    glowcamera = new THREE.PerspectiveCamera 75, SCREEN_WIDTH / SCREEN_HEIGHT, 1, 100000
    glowcamera.position = camera.position

    # BUILD SCENE
    particles = []
    spaceship = new Spaceship()
    spaceship.spawn scene, glowscene

    scene.add background

    grid = new Grid WORLD_BOUNDS.minX, WORLD_BOUNDS.minY, 1000, 1000, 20, 0xb8f35b, 0.1, 2
    grid.spawn scene, glowscene

    # GLOW COMPOSER
    renderTargetGlow = new THREE.WebGLRenderTarget SCREEN_WIDTH, SCREEN_HEIGHT, renderTargetParameters

    hblur = new THREE.ShaderPass THREE.ShaderExtras[ "horizontalBlur" ]
    vblur = new THREE.ShaderPass THREE.ShaderExtras[ "verticalBlur" ]

    bluriness = 2

    hblur.uniforms[ 'h' ].value = bluriness / SCREEN_WIDTH
    vblur.uniforms[ 'v' ].value = bluriness / SCREEN_HEIGHT

    renderModelGlow = new THREE.RenderPass glowscene, glowcamera

    glowcomposer = new THREE.EffectComposer renderer, renderTargetGlow

    glowcomposer.addPass renderModelGlow
    glowcomposer.addPass hblur
    glowcomposer.addPass vblur

    # FINAL COMPOSER
    finalshader.uniforms[ 'tGlow' ].texture = glowcomposer.renderTarget2

    renderTarget = new THREE.WebGLRenderTarget SCREEN_WIDTH, SCREEN_HEIGHT, renderTargetParameters
    
    initFinalComposer finalshader, scene, camera, renderer, renderTarget, renderTargetParameters

init = () ->
    bluriness = null
    renderModelGlow = null
    $container = null
    nextItem = null
    previousItem = null
    selectedItem = null

    container = document.createElement 'div'
    container.id = 'container'
    document.body.appendChild container

    $(document).keydown (e) ->
        if inMenu
            $container = $('.menu.current .menu-actions')
            if e.keyCode == 40 or e.keyCode == 83
                nextItem = $container.find('.selected').next()
                $container.find('li').removeClass('selected')

                if nextItem.length > 0
                    $(nextItem).addClass('selected')
                else
                    $container.find('li:first').addClass('selected')
            else if e.keyCode == 38 or e.keyCode == 87
                previousItem = $container.find('.selected').prev()
                $container.find('li').removeClass('selected')

                if previousItem.length > 0
                    $(previousItem).addClass('selected')
                else
                    $container.find('li:last').addClass('selected')
            else if e.keyCode == 13
                selectedItem = $container.find('.selected')
                window[selectedItem.data('action')]()
        else
            if e.keyCode == 68
                spaceship.rotation = 2.5
            else if e.keyCode == 65
                spaceship.rotation = -2.5
            else if e.keyCode == 87
                spaceship.velocity = 175
            else if e.keyCode == 32
                spaceship.shooting = true
            else if e.keyCode == 80
                if paused
                    unpause()
                else
                    pause()

    $(document).keyup (e) ->
        if inMenu
        else
            if e.keyCode == 68 or e.keyCode == 65
                spaceship.rotation = 0
            else if e.keyCode == 87
                spaceship.velocity = 0
            else if e.keyCode == 32
                spaceship.shooting = false

    # RENDERER
    renderer = new THREE.WebGLRenderer({
        #antialias: true
    })

    renderer.autoClear = false
    renderer.sortObjects = true
    renderer.setSize SCREEN_WIDTH, SCREEN_HEIGHT
    renderer.domElement.style.position = "relative"

    container.appendChild renderer.domElement

    # STATS

    stats = new Stats()
    stats.domElement.style.position = 'absolute'
    stats.domElement.style.top = '0px'
    stats.domElement.style.zIndex = 100
    container.appendChild stats.domElement

    window.addEventListener 'resize', onWindowResize, false
    document.addEventListener "webkitvisibilitychange", handleVisibilityChange, false

    # Load textures
    for name, texture of textures
        texture.texture = new THREE.Texture()
        loader = new THREE.ImageLoader()
        loader.addEventListener 'load', (e) ->
            texture.texture.image = e.content
            texture.texture.needsUpdate = true

        loader.load texture.url
        geometry = new THREE.PlaneGeometry(2000, 2000)
        geometry.position = new THREE.Vector3(0, 0, 0)
        material = new THREE.MeshBasicMaterial map: texture.texture, overdraw: true, opacity: 0.2
        background = new THREE.Mesh geometry, material

initFinalComposer = (finalShader, scene, camera, renderer, renderTarget, renderTargetParameters) ->
    renderModel = new THREE.RenderPass scene, camera

    finalPass = new THREE.ShaderPass finalshader
    finalPass.needsSwap = true

    finalPass.renderToScreen = true

    finalcomposer = new THREE.EffectComposer renderer, renderTarget

    if not paused
        finalcomposer.addPass renderModel

    finalcomposer.addPass finalPass

onWindowResize = () ->
    windowHalfX = window.innerWidth / 2
    windowHalfY = window.innerHeight / 2

    camera.aspect = window.innerWidth / window.innerHeight
    camera.updateProjectionMatrix()

    glowcamera.aspect = window.innerWidth / window.innerHeight
    glowcamera.updateProjectionMatrix()

    renderer.setSize window.innerWidth, window.innerHeight

handleVisibilityChange = () ->
  if document.webkitHidden and not inMenu
    pause()

animate = () ->
    update()
    render()
    stats.update()

    requestAnimationFrame animate

getSpawnPoint = (SPAWN_POINTS) ->
    numberOfSpawnPoints = SPAWN_POINTS.length
    spawnPoint = SPAWN_POINTS[parseInt(Math.random()*numberOfSpawnPoints, 10)]
    distanceFromSpaceship = spawnPoint.clone().subSelf(spaceship.position).length()

    while distanceFromSpaceship < 50
        spawnPoint = SPAWN_POINTS[parseInt(Math.random()*numberOfSpawnPoints, 10)]
        distanceFromSpaceship = spawnPoint.clone().subSelf(spaceship.position).length()

    spawnPoint

update = () ->
    now = null
    newX = null
    newY = null
    e = null
    p = null
    c = null
    babyCrossBoxesToAdd = []
    baby1 = null
    baby2 = null
    baby3 = null
    mainMenuRotation = 0.01

    if mainMenu
        spaceship.mesh.rotation.x += mainMenuRotation
        spaceship.mesh.rotation.y += mainMenuRotation
        spaceship.mesh.rotation.z += mainMenuRotation
        spaceship.glowMesh.rotation.x += mainMenuRotation
        spaceship.glowMesh.rotation.y += mainMenuRotation
        spaceship.glowMesh.rotation.z += mainMenuRotation

        for particle in particles
            unless particle.dead
                particle.update()

        if Math.random() < 0.2
            explosion new THREE.Vector3((Math.random()*200)-100,(Math.random()*200)-100,-200), MAIN_MENU_COLORS[Math.floor(Math.random()*MAIN_MENU_COLORS.length)], 0.5, 20, particles
    else
        spaceship.update scene, glowscene, WORLD_BOUNDS

        if paused
            now = (new Date()).getTime()
            newX = 100 * Math.sin now / 2000
            newY = 100 * Math.sin now / -3500

            camera.position.x = spaceship.position.x + newX
            camera.position.y = spaceship.position.y + newY
            for enemy in enemies
                enemy.update scene, glowscene, WORLD_BOUNDS
        else
            camera.position.x = spaceship.position.x
            camera.position.y = spaceship.position.y

            background.rotation.z += 0.0005

            if Math.random() < 0.01
                e = new DiamondEnemy(getSpawnPoint(SPAWN_POINTS), null, 0.8)
                replaceDead e, enemies
                e.spawn scene, glowscene

            if Math.random() < 0.01
                p = new PinWheelEnemy(getSpawnPoint(SPAWN_POINTS), null, 0.8)
                replaceDead p, enemies
                p.spawn scene, glowscene

            if Math.random() < 0.005
                c = new CrossBoxEnemy(getSpawnPoint(SPAWN_POINTS), null, 0.8)
                replaceDead c, enemies
                c.spawn scene, glowscene

            for enemy in enemies
                if not enemy.dead
                    enemy.update scene, glowscene, WORLD_BOUNDS
                    for bullet in spaceship.bullets
                        if not bullet.dead
                            bullet.collide enemy

            for particle in particles
                particle.update()

render = () ->
    glowcomposer.render 0.1
    finalcomposer.render 0.1

init()
buildMainMenuScene()
animate()

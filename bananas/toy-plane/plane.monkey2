
Namespace plane

#Import "<std>"
#Import "<mojo>"
#Import "<mojo3d>"

#Import "source/PlaneControl"

#Import "textures/"

#Import "models/plane/"

Using std..
Using mojo..
Using mojo3d..

Class MyWindow Extends Window
	
	Global _res :Vec2i
	
	Field _scene:Scene
	Field _camera:Camera
	Field _light:Light
	
	Field _water:Model
	Field _plane:Model
	Field _pivot:Model		'Needs to be a Model instead of Entity otherwise the plane isn't rendered!
		
	Field _camTarget:Entity
	
	Field test:Model
	
	Method New()
		Super.New( "Toy Plane", 1280, 720, WindowFlags.Resizable )' | WindowFlags.HighDPI  )
		_res = New Vec2i( Width, Height )
		Layout = "letterbox"
		
		_scene=New Scene
		_scene.SkyTexture=Texture.Load( "asset::miramar-skybox.jpg",TextureFlags.FilterMipmap|TextureFlags.Cubemap )
		_scene.EnvTexture = _scene.SkyTexture
		_scene.FogColor=New Color(0.69, 0.78, 0.82, 0.75 )
		_scene.FogNear=1
		_scene.FogFar=1000
		
		'create light
		_light=New Light
		_light.Rotate( 54,144,0 )	'calibrated to match sky texture!
		_light.CastsShadow = True
		
		'create water material
		Local waterMaterial:=New WaterMaterial
		
		waterMaterial.ScaleTextureMatrix( 100,100 )
		waterMaterial.ColorFactor=New Color( 0.05, 0.25, 0.3 )
		waterMaterial.Roughness=0
		
		waterMaterial.NormalTextures=New Texture[]( 
			Texture.Load( "asset::water_normal0.png",TextureFlags.WrapST | TextureFlags.FilterMipmap ),
			Texture.Load( "asset::water_normal1.png",TextureFlags.WrapST | TextureFlags.FilterMipmap ) )
		
		waterMaterial.Velocities=New Vec2f[]( 
			New Vec2f( .01,.03 ),
			New Vec2f( .02,.05 ) )
		
		'create water
		_water=Model.CreateBox( New Boxf( -2000,-1,-2000,2000,0,2000 ),1,1,1,waterMaterial )
		_water.CastsShadow=False
		
		'create bloom
		Local _bloom := New BloomEffect( 2 )
		_scene.AddPostEffect( _bloom )
		
		'create main pivot
		_pivot = New Model
		
		'create airplane
		_plane = Model.LoadBoned( "asset::plane.gltf" )
'		_plane.Animator.Animate( 0 )
		_plane.Parent = _pivot
		_plane.Position = New Vec3f

		'create camera target
		_camTarget = New Entity( _plane )
'		_camTarget = Model.CreateSphere( 0.25, 12, 12, New PbrMaterial( Color.Red ) )
		_camTarget.Parent = _plane
		_camTarget.Position = New Vec3f( 0, 0, 10 )

		'create camera
		_camera=New Camera( _pivot )
		_camera.Viewport=Rect
		_camera.Near=.1
		_camera.Far=1000
		_camera.FOV = 60
		_camera.Move( 0,3,-12 )
		
		'Control component
		Local control := _pivot.AddComponent<PlaneControl>()
		control.plane = _plane
		control.camera = _camera
		control.target = _camTarget

		_pivot.Position = New Vec3f( 0, 6, 0 )
	End
	
	
	Method OnRender( canvas:Canvas ) Override
		RequestRender()
		
		_camera.Viewport=Rect
		
		_water.Position=New Vec3f( Round(_camera.Position.x/2000)*2000,0,Round(_camera.Position.z/2000)*2000 )

		_camera.WorldPointAt( _camTarget.Position )
		
		_scene.Update()
		_scene.Render( canvas )
		
		canvas.DrawText( "Width="+Width+", Height="+Height+", FPS="+App.FPS,0,0 )
'		canvas.DrawText( _plane.Rotation,0,15 )
'		canvas.DrawText( _plane.LocalRotation,0,30 )
	End
	
'	
	Method OnMeasure:Vec2i() Override
		Return _res
	End
	
End


Class Entity Extension
	
	Method WorldPointAt( target:Vec3f,up:Vec3f=New Vec3f( 0,1,0 ) )
		Local k:=(target-Position).Normalize()
		Local i:=up.Cross( k ).Normalize()
		Local j:=k.Cross( i )
		Basis=New Mat3f( i,j,k )
	End

End

Function Main()
	
	New AppInstance
	
	New MyWindow
	
	App.Run()
End


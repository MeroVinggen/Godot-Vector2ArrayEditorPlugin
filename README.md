<p align="center">
  <img src="./icon.svg"  height="100" alt="Godot-Vector2EditorPlugin Icon"/>
</p>

<h1 align="center">
  Godot Vector2Editor Plugin
</h1>

<p align="center">
  <a href="https://ko-fi.com/I2I31KH5HB" target="_blank">
	<img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support me on Ko-fi"/>
  </a>
</p>


## About

Edit Array[Vector2] and PackedVector2Array directly in the editor as if they were polygons—no extra nodes, no complex setup. Just enable, drag, add, or remove points right on the canvas.


## Demo Preview 

![demo-preview1](./github-materials/demo.gif)


## Features

- Easy to use - simply install, enable and you are ready to go!
- Edit `Array[Vector2]` and `PackedVector2Array` with power of polygons editing
- support for CanvasItem nodes (Node2D, Control and any of their subtype)
- Doesn't impact project performance or complexity


## Requirements 

- Godot 4.2 or higher
  

## Installation

- Open the `AssetLib` tab in Godot with your project open.
- Search for "Vector2 array editor" and install the plugin by Mero.
- Open project settings -> plugins, and enable the plugin `Vector2ArrayEditor`.
- Done!


## Usage

> [!WARNING]
> Make sure to check [Troubleshooting](#Troubleshooting) section

```gdscript 
# in your Node2D script

@export var arr1: Array[Vector2]
@export var arr2: PackedVector2Array
```

- select any node in your scene with exported `Array[Vector2]` or `PackedVector2Array` property type

- click "Edit in 2D view" button in the inspector right above your property to enter edit mode 

![edit-btn-screenshot](./github-materials/screenshot1.png)

- if there is less then 3 items in your array the button will add missing points (it won't override existing ones)

![add-btn-screenshot](./github-materials/screenshot2.png)


## Troubleshooting

- plugin support only CanvasItem nodes, e.g. Node2D, Control and any of their subtype. For all the other the edit btn will be blocked 
- plugin support only `Array[Vector2]` or `PackedVector2Array` types and won't work if you have like array of `Vector2` without explicit type 
- if the node was already in focus before enabling the plugin - refocus it to see the edit buttons

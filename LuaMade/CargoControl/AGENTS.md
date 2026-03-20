# CargoControl
CargoControl is a GUI-based logistics management system for LuaMade computers with a reusable GUI library.

## GUI Library (gui_lib.lua)

A reusable, object-oriented GUI framework built on the LuaMade Graphics API with automatic resizing support.

**Key Features:**
- Automatic rescaling every draw frame to match window size changes
- Console clearing to prevent unwanted text input interference
- Layered rendering system (Background, Panels, Components, Overlay, Effects)
- Reusable components: Panel, Button, Text, HorizontalLayout, VerticalLayout
- GUIManager for rendering loop and component management

**Components:**
- `GUIManager`: Main controller for GUI rendering and events
- `Component`: Base class for all UI elements  
- `Panel`: Container component with title and border
- `Button`: Interactive button with hover/pressed states
- `Text`: Text display with color customization
- `HorizontalLayout`: Auto-layout for horizontal arrangement
- `VerticalLayout`: Auto-layout for vertical arrangement

**Files:**
- `gui_lib.lua`: Core library implementation
- `gui_demo.lua`: Example logistics dashboard using GUI library

CargoControl is a GUI-based logistics management system for LuaMade computers. It allows users to automate and control their logistics via a request-based system. It can assign shipyards to replenish and repair fleets, automate cargo delivery between bases, and more.

# LuaMade
LuaMade is a ComputerCraft-style mod for StarMade that adds scriptable Lua computers to the game.
LuaMade API Documentation is available at https://garretreichenbach.github.io/Logiscript/
package flixel.text;

import flixel.input.FlxPointer;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.frontEnds.InputTextFrontEnd;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import lime.system.Clipboard;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.text.TextFormat;
import openfl.utils.QName;

class FlxInputText extends FlxText implements IFlxInputText
{
	public static inline var BACKSPACE_ACTION:String = "backspace";
	
	public static inline var DELETE_ACTION:String = "delete";
	
	public static inline var ENTER_ACTION:String = "enter";
	
	public static inline var INPUT_ACTION:String = "input";

	static inline var GUTTER:Int = 2;
	
	static final DELIMITERS:Array<String> = ['\n', '.', '!', '?', ',', ' ', ';', ':', '(', ')', '-', '_', '/'];
	
	public var bottomScrollV(get, never):Int;
	
	public var callback:String->String->Void;
	
	public var caretColor(default, set):FlxColor = FlxColor.WHITE;
	
	public var caretIndex(get, set):Int;
	
	public var caretWidth(default, set):Int = 1;
	
	public var hasFocus(default, set):Bool = false;
	
	public var maxLength(default, set):Int = 0;

	public var maxScrollH(get, never):Int;
	
	public var maxScrollV(get, never):Int;
	
	public var multiline(get, set):Bool;
	
	public var passwordMode(get, set):Bool;

	public var scrollH(get, set):Int;
	
	public var scrollV(get, set):Int;

	public var selectedTextColor(default, set):FlxColor = FlxColor.WHITE;
	
	public var selectionBeginIndex(get, never):Int;

	public var selectionColor(default, set):FlxColor = FlxColor.BLACK;
	
	public var selectionEndIndex(get, never):Int;
	
	var _caret:FlxSprite;
	var _caretIndex:Int = -1;
	var _lastClickTime:Int = 0;
	var _mouseDown:Bool = false;
	var _pointerCamera:FlxCamera;
	var _scrollVCounter:Float = 0;
	var _selectionBoxes:Array<FlxSprite> = [];
	var _selectionFormat:TextFormat = new TextFormat();
	var _selectionIndex:Int = -1;
	
	public function new(x:Float = 0, y:Float = 0, fieldWidth:Float = 0, ?text:String, size:Int = 8, embeddedFont:Bool = true)
	{
		super(x, y, fieldWidth, text, size, embeddedFont);
		
		// If the text field's type isn't INPUT and there's a new line at the end
		// of the text, it won't be counted for in `numLines`
		textField.type = INPUT;
		
		_selectionFormat.color = selectedTextColor;
		
		_caret = new FlxSprite();
		_caret.visible = false;
		regenCaret();
		updateCaretPosition();
		
		FlxG.inputText.registerInputText(this);
	}
	
	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		
		#if FLX_MOUSE
		if (visible)
		{
			updateInput(elapsed);
		}
		#end
	}
	
	override function draw():Void
	{
		for (box in _selectionBoxes)
			drawSprite(box);

		super.draw();
		
		drawSprite(_caret);
	}
	
	override function destroy():Void
	{
		FlxG.inputText.unregisterInputText(this);

		_caret = FlxDestroyUtil.destroy(_caret);
		_pointerCamera = null;
		while (_selectionBoxes.length > 0)
			FlxDestroyUtil.destroy(_selectionBoxes.pop());
		_selectionBoxes = null;
		_selectionFormat = null;
		
		super.destroy();
	}

	override function applyFormats(formatAdjusted:TextFormat, useBorderColor:Bool = false):Void
	{
		// scroll variables will be reset when `textField.setTextFormat()` is called,
		// cache the current ones first
		var cacheScrollH = scrollH;
		var cacheScrollV = scrollV;
		
		super.applyFormats(formatAdjusted, useBorderColor);
		
		textField.setTextFormat(_selectionFormat, selectionBeginIndex, selectionEndIndex);
		// set the scroll back to how it was
		scrollH = cacheScrollH;
		scrollV = cacheScrollV;
	}
	
	override function regenGraphic():Void
	{
		var regenSelection = _regen;
		
		super.regenGraphic();
		
		if (_caret != null && regenSelection)
			updateSelectionSprites();
	}
	
	public function dispatchTypingAction(action:TypingAction):Void
	{
		switch (action)
		{
			case ADD_TEXT(newText):
				addText(newText);
			case MOVE_CURSOR(type, shiftKey):
				moveCursor(type, shiftKey);
			case COMMAND(cmd):
				runCommand(cmd);
		}
	}

	public function setSelection(beginIndex:Int, endIndex:Int):Void
	{
		_selectionIndex = beginIndex;
		_caretIndex = endIndex;
		
		if (textField == null)
			return;

		updateSelection();
	}
	function addText(newText:String):Void
	{
		newText = filterText(newText);
		if (newText.length > 0)
		{
			replaceSelectedText(newText);
			onChange(INPUT_ACTION);
		}
	}
	
	function drawSprite(sprite:FlxSprite):Void
	{
		if (sprite != null && sprite.visible)
		{
			sprite.scrollFactor.copyFrom(scrollFactor);
			sprite._cameras = _cameras;
			sprite.draw();
		}
	}
	function filterText(newText:String):String
	{
		if (maxLength > 0)
		{
			var removeLength = (selectionEndIndex - selectionBeginIndex);
			var newMaxLength = maxLength - text.length + removeLength;
			
			if (newMaxLength <= 0)
			{
				newText = "";
			}
			else if (newMaxLength < newText.length)
			{
				newText = newText.substr(0, newMaxLength);
			}
		}
		
		return newText;
	}
	
	function getCharIndexOnDifferentLine(charIndex:Int, lineIndex:Int):Int
	{
		if (charIndex < 0 || charIndex > text.length)
			return -1;
		if (lineIndex < 0 || lineIndex > textField.numLines - 1)
			return -1;
			
		var x = 0.0;
		var charBoundaries = textField.getCharBoundaries(charIndex - 1);
		if (charBoundaries != null)
		{
			x = charBoundaries.right;
		}
		else
		{
			x = GUTTER;
		}
		
		var y = GUTTER + getLineY(lineIndex) + textField.getLineMetrics(lineIndex).height / 2 - getLineY(scrollV - 1);
		
		return getCharAtPosition(x, y);
	}
	
	function getCharAtPosition(x:Float, y:Float):Int
	{
		x += scrollH;
		y += getLineY(scrollV - 1);
		
		if (x < GUTTER)
			x = GUTTER;

		if (y > textField.textHeight)
			y = textField.textHeight;
		if (y < GUTTER)
			y = GUTTER;

		for (line in 0...textField.numLines)
		{
			var lineY = GUTTER + getLineY(line);
			var lineOffset = textField.getLineOffset(line);
			var lineHeight = textField.getLineMetrics(line).height;
			if (y >= lineY && y <= lineY + lineHeight)
			{
				// check for every character in the line
				var lineLength = textField.getLineLength(line);
				var lineEndIndex = lineOffset + lineLength;
				for (char in 0...lineLength)
				{
					var boundaries = textField.getCharBoundaries(lineOffset + char);
					// reached end of line, return this character
					if (boundaries == null)
						return lineOffset + char;
					if (x <= boundaries.right)
					{
						if (x <= boundaries.x + (boundaries.width / 2))
						{
							return lineOffset + char;
						}
						else
						{
							return (lineOffset + char < lineEndIndex) ? lineOffset + char + 1 : lineEndIndex;
						}
					}
				}
				
				// a character wasn't found, return the last character of the line
				return lineEndIndex;
			}
		}
		
		return text.length;
	}

	function getLineY(line:Int):Float
	{
		var scrollY = 0.0;
		for (i in 0...line)
		{
			scrollY += textField.getLineMetrics(i).height;
		}
		return scrollY;
	}

	function isCaretLineVisible():Bool
	{
		var line = textField.getLineIndexOfChar(_caretIndex);
		return line >= scrollV - 1 && line <= bottomScrollV - 1;
	}
	
	function moveCursor(type:MoveCursorAction, shiftKey:Bool):Void
	{
		switch (type)
		{
			case LEFT:
				if (_caretIndex > 0)
				{
					_caretIndex--;
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case RIGHT:
				if (_caretIndex < text.length)
				{
					_caretIndex++;
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case UP:
				var lineIndex = textField.getLineIndexOfChar(_caretIndex);
				if (lineIndex > 0)
				{
					_caretIndex = getCharIndexOnDifferentLine(_caretIndex, lineIndex - 1);
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case DOWN:
				var lineIndex = textField.getLineIndexOfChar(_caretIndex);
				if (lineIndex < textField.numLines - 1)
				{
					_caretIndex = getCharIndexOnDifferentLine(_caretIndex, lineIndex + 1);
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case HOME:
				_caretIndex = 0;
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case END:
				_caretIndex = text.length;
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case LINE_BEGINNING:
				_caretIndex = textField.getLineOffset(textField.getLineIndexOfChar(_caretIndex));
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case LINE_END:
				var lineIndex = textField.getLineIndexOfChar(_caretIndex);
				if (lineIndex < textField.numLines - 1)
				{
					_caretIndex = textField.getLineOffset(lineIndex + 1) - 1;
				}
				else
				{
					_caretIndex = text.length;
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case PREVIOUS_LINE:
				var lineIndex = textField.getLineIndexOfChar(_caretIndex);
				if (lineIndex > 0)
				{
					var index = textField.getLineOffset(lineIndex);
					if (_caretIndex == index)
					{
						_caretIndex = textField.getLineOffset(lineIndex - 1);
					}
					else
					{
						_caretIndex = index;
					}
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case NEXT_LINE:
				var lineIndex = textField.getLineIndexOfChar(_caretIndex);
				if (lineIndex < textField.numLines - 1)
				{
					_caretIndex = textField.getLineOffset(lineIndex + 1);
				}
				else
				{
					_caretIndex = text.length;
				}
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
		}
	}
	function onChange(action:String):Void
	{
		if (callback != null)
			callback(text, action);
	}
	
	function regenCaret():Void
	{
		_caret.makeGraphic(caretWidth, Std.int(size + 2), FlxColor.WHITE);
	}

	function replaceSelectedText(newText:String):Void
	{
		if (newText == null)
			newText = "";
		if (newText == "" && _selectionIndex == _caretIndex)
			return;
			
		var beginIndex = selectionBeginIndex;
		var endIndex = selectionEndIndex;
		
		if (beginIndex == endIndex && maxLength > 0 && text.length == maxLength)
			return;

		if (beginIndex < 0)
		{
			beginIndex = 0;
		}
		
		replaceText(beginIndex, endIndex, newText);
	}
	
	function replaceText(beginIndex:Int, endIndex:Int, newText:String):Void
	{
		if (endIndex < beginIndex || beginIndex < 0 || endIndex > text.length || newText == null)
			return;

		text = text.substring(0, beginIndex) + newText + text.substring(endIndex);
		
		_selectionIndex = _caretIndex = beginIndex + newText.length;
		setSelection(_selectionIndex, _caretIndex);
	}
	
	function runCommand(cmd:TypingCommand):Void
	{
		switch (cmd)
		{
			case NEW_LINE:
				if (multiline)
				{
					addText("\n");
				}
				onChange(ENTER_ACTION);
			case DELETE_LEFT:
				if (_selectionIndex == _caretIndex && _caretIndex > 0)
				{
					_selectionIndex = _caretIndex - 1;
				}
				
				if (_selectionIndex != _caretIndex)
				{
					replaceSelectedText("");
					_selectionIndex = _caretIndex;
					onChange(BACKSPACE_ACTION);
				}
			case DELETE_RIGHT:
				if (_selectionIndex == _caretIndex && _caretIndex < text.length)
				{
					_selectionIndex = _caretIndex + 1;
				}
				
				if (_selectionIndex != _caretIndex)
				{
					replaceSelectedText("");
					_selectionIndex = _caretIndex;
					onChange(DELETE_ACTION);
				}
			case COPY:
				if (_caretIndex != _selectionIndex && !passwordMode)
				{
					Clipboard.text = text.substring(_caretIndex, _selectionIndex);
				}
			case CUT:
				if (_caretIndex != _selectionIndex && !passwordMode)
				{
					Clipboard.text = text.substring(_caretIndex, _selectionIndex);
					
					replaceSelectedText("");
				}
			case PASTE:
				if (Clipboard.text != null)
				{
					addText(Clipboard.text);
				}
			case SELECT_ALL:
				_selectionIndex = 0;
				_caretIndex = text.length;
				setSelection(_selectionIndex, _caretIndex);
		}
	}
	
	function updateCaretPosition():Void
	{
		if (textField == null)
			return;
			
		if (text.length == 0)
		{
			_caret.setPosition(x + GUTTER, y + GUTTER);
		}
		else
		{
			var boundaries = textField.getCharBoundaries(_caretIndex - 1);
			if (boundaries != null)
			{
				_caret.setPosition(x + boundaries.right - scrollH, y + boundaries.y - getLineY(scrollV - 1));
			}
			else // end of line
			{
				var lineIndex = textField.getLineIndexOfChar(_caretIndex);
				_caret.setPosition(x + GUTTER, y + GUTTER + getLineY(lineIndex) - getLineY(scrollV - 1));
			}
		}
	}
	
	function updateSelection():Void
	{
		textField.setSelection(_selectionIndex, _caretIndex);
		_regen = true;
	}
	
	function updateSelectionBoxes():Void
	{
		if (textField == null)
			return;
			
		while (_selectionBoxes.length > textField.numLines)
		{
			var box = _selectionBoxes.pop();
			if (box != null)
				box.destroy();
		}
		
		if (_caretIndex == _selectionIndex)
		{
			for (box in _selectionBoxes)
			{
				if (box != null)
					box.visible = false;
			}
			
			return;
		}
		
		var beginLine = textField.getLineIndexOfChar(selectionBeginIndex);
		var endLine = textField.getLineIndexOfChar(selectionEndIndex);
		
		var scrollY = getLineY(scrollV - 1);
		
		for (line in 0...textField.numLines)
		{
			var box = _selectionBoxes[line];
			if ((line >= scrollV - 1 && line <= bottomScrollV - 1) && (line >= beginLine && line <= endLine))
			{
				var lineStartIndex = textField.getLineOffset(line);
				var lineEndIndex = lineStartIndex + textField.getLineLength(line);
				
				var startIndex = FlxMath.maxInt(lineStartIndex, selectionBeginIndex);
				var endIndex = FlxMath.minInt(lineEndIndex, selectionEndIndex);
				
				var startBoundaries = textField.getCharBoundaries(startIndex);
				var endBoundaries = textField.getCharBoundaries(endIndex - 1);
				if (endBoundaries == null && endIndex > startIndex) // end of line, try getting the previous character
				{
					endBoundaries = textField.getCharBoundaries(endIndex - 2);
				}
				
				if (startBoundaries != null && endBoundaries != null)
				{
					if (box == null)
					{
						box = _selectionBoxes[line] = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
						box.color = selectionColor;
					}
						
					var boxRect = FlxRect.get(startBoundaries.x - scrollH, startBoundaries.y - scrollY, endBoundaries.right - startBoundaries.x,
						startBoundaries.height);
					boxRect.clipTo(FlxRect.weak(0, 0, width, height)); // clip the selection box inside the text sprite
					
					box.setPosition(x + boxRect.x, y + boxRect.y);
					box.setGraphicSize(boxRect.width, boxRect.height);
					box.updateHitbox();
					box.visible = true;

					boxRect.put();
				}
				else if (box != null)
				{
					box.visible = false;
				}
			}
			else if (box != null)
			{
				box.visible = false;
			}
		}
	}
	
	function updateSelectionSprites():Void
	{
		_caret.alpha = (_selectionIndex == _caretIndex && isCaretLineVisible()) ? 1 : 0;
		updateCaretPosition();
		updateSelectionBoxes();
	}
	
	#if FLX_MOUSE
	function updateInput(elapsed:Float):Void
	{
		if (_mouseDown)
		{
			updatePointerDrag(FlxG.mouse, elapsed);

			if (FlxG.mouse.justMoved)
			{
				updatePointerMove(FlxG.mouse);
			}
			
			if (FlxG.mouse.released)
			{
				_mouseDown = false;
				updatePointerRelease(FlxG.mouse);
			}
		}
		if (checkPointerOverlap(FlxG.mouse))
		{
			if (FlxG.mouse.justPressed)
			{
				_mouseDown = true;
				updatePointerPress(FlxG.mouse);
				var currentTime = FlxG.game.ticks;
				if (currentTime - _lastClickTime < 500)
				{
					updatePointerDoublePress(FlxG.mouse);
					_lastClickTime = 0;
				}
				else
				{
					_lastClickTime = currentTime;
				}
			}
			
			if (FlxG.mouse.wheel != 0)
			{
				scrollV = FlxMath.minInt(scrollV - FlxG.mouse.wheel, maxScrollV);
			}
		}
		else if (FlxG.mouse.justPressed)
		{
			hasFocus = false;
		}
	}
	
	function checkPointerOverlap(pointer:FlxPointer):Bool
	{
		var overlap = false;
		var pointerPos = FlxPoint.get();
		for (camera in getCameras())
		{
			pointer.getWorldPosition(camera, pointerPos);
			if (overlapsPoint(pointerPos, true, camera))
			{
				if (_pointerCamera == null)
					_pointerCamera = camera;
				overlap = true;
				break;
			}
		}

		pointerPos.put();
		return overlap;
	}
	
	function updatePointerPress(pointer:FlxPointer):Void
	{
		hasFocus = true;
		
		var relativePos = getRelativePosition(pointer);
		_caretIndex = getCharAtPosition(relativePos.x, relativePos.y);
		_selectionIndex = _caretIndex;
		setSelection(_selectionIndex, _caretIndex);
		
		relativePos.put();
	}
	function updatePointerDrag(pointer:FlxPointer, elapsed:Float)
	{
		var relativePos = getRelativePosition(pointer);
		
		if (relativePos.x > width - 1)
		{
			scrollH += Std.int(Math.max(Math.min((relativePos.x - width) * .1, 10), 1));
		}
		else if (relativePos.x < 1)
		{
			scrollH -= Std.int(Math.max(Math.min(relativePos.x * -.1, 10), 1));
		}
		
		_scrollVCounter += elapsed;
		
		if (_scrollVCounter > 0.1)
		{
			if (relativePos.y > height - 2)
			{
				scrollV = Std.int(Math.min(scrollV + Math.max(Math.min((relativePos.y - height) * .03, 5), 1), maxScrollV));
			}
			else if (relativePos.y < 2)
			{
				scrollV -= Std.int(Math.max(Math.min(relativePos.y * -.03, 5), 1));
			}
			_scrollVCounter = 0;
		}
	}
	
	function updatePointerMove(pointer:FlxPointer):Void
	{
		if (_selectionIndex < 0)
			return;
			
		var relativePos = getRelativePosition(pointer);
		
		var char = getCharAtPosition(relativePos.x, relativePos.y);
		if (char != _caretIndex)
		{
			_caretIndex = char;
			updateSelection();
		}

		relativePos.put();
	}
	
	function updatePointerRelease(pointer:FlxPointer):Void
	{
		if (!hasFocus)
			return;
			
		var relativePos = getRelativePosition(pointer);
		
		var upPos = getCharAtPosition(relativePos.x, relativePos.y);
		var leftPos = FlxMath.minInt(_selectionIndex, upPos);
		var rightPos = FlxMath.maxInt(_selectionIndex, upPos);
		
		_selectionIndex = leftPos;
		_caretIndex = rightPos;

		relativePos.put();
		_pointerCamera = null;
	}
	
	function updatePointerDoublePress(pointer:FlxPointer):Void
	{
		var rightPos = text.length;
		if (text.length > 0 && _caretIndex >= 0 && rightPos >= _caretIndex)
		{
			var leftPos = -1;
			var pos = 0;
			var startPos = FlxMath.maxInt(_caretIndex, 1);
			
			for (c in DELIMITERS)
			{
				pos = text.lastIndexOf(c, startPos - 1);
				if (pos > leftPos)
					leftPos = pos + 1;
					
				pos = text.indexOf(c, startPos);
				if (pos < rightPos && pos != -1)
					rightPos = pos;
			}
			
			if (leftPos != rightPos)
			{
				setSelection(leftPos, rightPos);
			}
		}
	}
	
	function getRelativePosition(pointer:FlxPointer):FlxPoint
	{
		var pointerPos = pointer.getWorldPosition(_pointerCamera);
		getScreenPosition(_point, _pointerCamera);
		var result = FlxPoint.get(pointerPos.x - _point.x, pointerPos.y - _point.y);
		pointerPos.put();
		return result;
	}
	#end
	
	override function set_color(value:FlxColor):FlxColor
	{
		if (color != value)
		{
			super.set_color(value);
			caretColor = value;
		}
		
		return value;
	}
	
	override function set_text(value:String):String
	{
		if (text != value)
		{
			super.set_text(value);
			
			if (hasFocus)
			{
				if (text.length < _selectionIndex)
				{
					_selectionIndex = text.length;
				}
				if (text.length < _caretIndex)
				{
					_caretIndex = text.length;
				}
			}
			else
			{
				_selectionIndex = 0;
				_caretIndex = 0;
			}
			setSelection(_selectionIndex, _caretIndex);
		}
		
		return value;
	}

	function get_bottomScrollV():Int
	{
		return textField.bottomScrollV;
	}
	
	function set_caretColor(value:FlxColor):FlxColor
	{
		if (caretColor != value)
		{
			caretColor = value;
			_caret.color = caretColor;
		}

		return value;
	}
	
	function get_caretIndex():Int
	{
		return _caretIndex;
	}

	function set_caretIndex(value:Int):Int
	{
		if (_caretIndex != value)
		{
			_caretIndex = value;
			if (_caretIndex < 0)
				_caretIndex = 0;
			if (_caretIndex > text.length)
				_caretIndex = text.length;
			setSelection(_caretIndex, _caretIndex);
		}

		return value;
	}
	
	function set_caretWidth(value:Int):Int
	{
		if (caretWidth != value)
		{
			caretWidth = value;
			regenCaret();
		}

		return value;
	}
	
	function set_hasFocus(value:Bool):Bool
	{
		if (hasFocus != value)
		{
			hasFocus = value;
			if (hasFocus)
			{
				FlxG.inputText.focus = this;
				
				if (_caretIndex < 0)
				{
					_caretIndex = text.length;
					_selectionIndex = _caretIndex;
					setSelection(_selectionIndex, _caretIndex);
				}
				
				_caret.visible = true;
			}
			else if (FlxG.inputText.focus == this)
			{
				FlxG.inputText.focus = null;
				
				if (_selectionIndex != _caretIndex)
				{
					_selectionIndex = _caretIndex;
					setSelection(_selectionIndex, _caretIndex);
				}
				
				_caret.visible = false;
			}
		}

		return value;
	}
	
	function set_maxLength(value:Int):Int
	{
		if (maxLength != value)
		{
			maxLength = value;
			if (maxLength > 0 && text.length > maxLength)
			{
				text = text.substr(0, maxLength);
			}
		}
		
		return value;
	}

	function get_maxScrollH():Int
	{
		return textField.maxScrollH;
	}
	
	function get_maxScrollV():Int
	{
		return textField.maxScrollV;
	}
	
	function get_multiline():Bool
	{
		return textField.multiline;
	}
	
	function set_multiline(value:Bool):Bool
	{
		if (textField.multiline != value)
		{
			textField.multiline = value;
		}

		return value;
	}
	
	function get_passwordMode():Bool
	{
		return textField.displayAsPassword;
	}
	
	function set_passwordMode(value:Bool):Bool
	{
		if (textField.displayAsPassword != value)
		{
			textField.displayAsPassword = value;
			_regen = true;
		}
		return value;
	}

	function get_scrollH():Int
	{
		return textField.scrollH;
	}
	
	function set_scrollH(value:Int):Int
	{
		if (value > maxScrollH)
			value = maxScrollH;
		if (value < 0)
			value = 0;
		if (textField.scrollH != value)
		{
			textField.scrollH = value;
			_regen = true;
		}
		return value;
	}
	
	function get_scrollV():Int
	{
		return textField.scrollV;
	}
	
	function set_scrollV(value:Int):Int
	{
		if (value > maxScrollV)
			value = maxScrollV;
		if (value < 1)
			value = 1;
		if (textField.scrollV != value || textField.scrollV == 0)
		{
			textField.scrollV = value;
			_regen = true;
		}
		return value;
	}
	
	function set_selectedTextColor(value:FlxColor):FlxColor
	{
		if (selectedTextColor != value)
		{
			selectedTextColor = value;
			_selectionFormat.color = selectedTextColor;
			_regen = true;
		}
		
		return value;
	}
	
	function get_selectionBeginIndex():Int
	{
		return FlxMath.minInt(_caretIndex, _selectionIndex);
	}
	
	function set_selectionColor(value:FlxColor):FlxColor
	{
		if (selectionColor != value)
		{
			selectionColor = value;
			for (box in _selectionBoxes)
			{
				if (box != null)
					box.color = selectionColor;
			}
		}
		
		return value;
	}
	
	function get_selectionEndIndex():Int
	{
		return FlxMath.maxInt(_caretIndex, _selectionIndex);
	}
}

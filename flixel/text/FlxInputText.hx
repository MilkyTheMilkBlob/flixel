package flixel.text;

import flixel.input.FlxPointer;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.frontEnds.InputTextFrontEnd;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxTimer;
import lime.system.Clipboard;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.text.TextFormat;
import openfl.utils.QName;

class FlxInputText extends FlxText implements IFlxInputText
{
	static inline var GUTTER:Int = 2;
	
	static final DELIMITERS:Array<String> = ['\n', '.', '!', '?', ',', ' ', ';', ':', '(', ')', '-', '_', '/'];
	
	public var background(default, set):Bool = false;
	
	public var backgroundColor(default, set):FlxColor = FlxColor.TRANSPARENT;
	
	public var bottomScrollV(get, never):Int;
	
	public var callback:String->FlxInputTextAction->Void;
	
	public var caretColor(default, set):FlxColor = FlxColor.WHITE;
	
	public var caretIndex(get, set):Int;
	
	public var caretWidth(default, set):Int = 1;
	
	public var customFilterPattern(default, set):EReg;

	public var editable:Bool = true;
	
	public var fieldBorderColor(default, set):FlxColor = FlxColor.BLACK;
	
	public var fieldBorderThickness(default, set):Int = 1;
	
	public var filterMode(default, set):FlxInputTextFilterMode = NO_FILTER;
	
	public var focusGained:Void->Void;
	
	public var focusLost:Void->Void;
	
	public var forceCase(default, set):FlxInputTextCase = ALL_CASES;
	
	public var hasFocus(default, set):Bool = false;
	
	public var maxLength(default, set):Int = 0;

	public var maxScrollH(get, never):Int;
	
	public var maxScrollV(get, never):Int;
	
	public var multiline(get, set):Bool;
	
	public var passwordMode(get, set):Bool;

	public var scrollH(get, set):Int;
	
	public var scrollV(get, set):Int;

	public var selectable:Bool = true;

	public var selectedTextColor(default, set):FlxColor = FlxColor.WHITE;
	
	public var selectionBeginIndex(get, never):Int;

	public var selectionColor(default, set):FlxColor = FlxColor.BLACK;
	
	public var selectionEndIndex(get, never):Int;

	/**
	 * If `false`, no extra format will be applied for selected text.
	 * 
	 * Useful if you are using `addFormat()`, as the selected text format might
	 * overwrite some of their properties.
	 */
	public var useSelectedTextFormat(default, set):Bool = true;
	
	var _backgroundSprite:FlxSprite;
	var _caret:FlxSprite;
	var _caretFlash:Bool = false;
	var _caretIndex:Int = -1;
	var _caretTimer:FlxTimer = new FlxTimer();
	var _fieldBorderSprite:FlxSprite;
	var _lastClickTime:Int = 0;
	var _mouseDown:Bool = false;
	var _pointerCamera:FlxCamera;
	var _regenBackground:Bool = false;
	var _scrollVCounter:Float = 0;
	var _selectionBoxes:Array<FlxSprite> = [];
	var _selectionFormat:TextFormat = new TextFormat();
	var _selectionIndex:Int = -1;
	
	public function new(x:Float = 0, y:Float = 0, fieldWidth:Float = 0, ?text:String, size:Int = 8, textColor:FlxColor = FlxColor.BLACK,
			backgroundColor:FlxColor = FlxColor.WHITE, embeddedFont:Bool = true)
	{
		super(x, y, fieldWidth, text, size, embeddedFont);
		this.backgroundColor = backgroundColor;
		
		wordWrap = multiline = false;
		// If the text field's type isn't INPUT and there's a new line at the end
		// of the text, it won't be counted for in `numLines`
		textField.type = INPUT;
		
		_selectionFormat.color = selectedTextColor;
		
		_caret = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		_caret.visible = false;
		updateCaretSize();
		updateCaretPosition();
		
		color = textColor;
		
		if (backgroundColor != FlxColor.TRANSPARENT)
		{
			background = true;
		}
		
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
		regenGraphic();

		drawSprite(_fieldBorderSprite);
		drawSprite(_backgroundSprite);

		for (box in _selectionBoxes)
			drawSprite(box);

		super.draw();
		
		drawSprite(_caret);
	}
	
	override function destroy():Void
	{
		FlxG.inputText.unregisterInputText(this);

		_backgroundSprite = FlxDestroyUtil.destroy(_backgroundSprite);
		_caret = FlxDestroyUtil.destroy(_caret);
		if (_caretTimer != null)
		{
			_caretTimer.cancel();
			_caretTimer = FlxDestroyUtil.destroy(_caretTimer);
		}
		_fieldBorderSprite = FlxDestroyUtil.destroy(_fieldBorderSprite);
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
		
		if (!useBorderColor && useSelectedTextFormat && selectionEndIndex > selectionBeginIndex)
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
		if (_regenBackground)
			regenBackground();
	}
	
	public function dispatchTypingAction(action:TypingAction):Void
	{
		switch (action)
		{
			case ADD_TEXT(newText):
				if (editable)
				{
					addText(newText);
				}
			case MOVE_CURSOR(type, shiftKey):
				moveCursor(type, shiftKey);
			case COMMAND(cmd):
				runCommand(cmd);
		}
	}

	public function replaceSelectedText(newText:String):Void
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
		newText = filterText(newText, true);
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

	function filterText(newText:String, selection:Bool = false):String
	{
		if (maxLength > 0)
		{
			var removeLength = selection ? (selectionEndIndex - selectionBeginIndex) : text.length;
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
		
		if (forceCase == UPPER_CASE)
		{
			newText = newText.toUpperCase();
		}
		else if (forceCase == LOWER_CASE)
		{
			newText = newText.toLowerCase();
		}
		
		if (filterMode != NO_FILTER)
		{
			var pattern = switch (filterMode)
			{
				case ONLY_ALPHA:
					~/[^a-zA-Z]*/g;
				case ONLY_NUMERIC:
					~/[^0-9]*/g;
				case ONLY_ALPHANUMERIC:
					~/[^a-zA-Z0-9]*/g;
				case CUSTOM_FILTER:
					customFilterPattern;
				default:
					throw "Unknown filterMode (" + filterMode + ")";
			}
			if (pattern != null)
				newText = pattern.replace(newText, "");
		}
		
		return newText;
	}

	function getCaretOffsetX():Float
	{
		return switch (alignment)
		{
			case CENTER: (width / 2);
			case RIGHT: width - GUTTER;
			default: GUTTER;
		}
	}

	function getCharAtPosition(x:Float, y:Float):Int
	{
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
					var boundaries = getCharBoundaries(lineOffset + char);
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

	/**
	 * NOTE: On Flash, this will not give the correct Y for characters that are out-of-view,
	 * due to needing to internally change the vertical scroll to get their boundaries.
	 * You should use `getLineY()` and `getScrollVOffset()` instead for getting the proper Y position.
	 */
	function getCharBoundaries(char:Int):Rectangle
	{
		#if flash
		// On Flash, `getCharBoundaries()` always returns null if the character is before
		// the current vertical scroll. Let's just set the scroll directly at the line
		// and change it back later
		var cacheScrollV = scrollV;
		// Change the internal text field's property instead to not cause a loop due to `_regen`
		// always being set back to true
		textField.scrollV = getLineIndexOfChar(char) + 1;
		var prevRegen = _regen;
		#end
		
		var boundaries = textField.getCharBoundaries(char);
		if (boundaries == null)
		{
			#if flash
			textField.scrollV = cacheScrollV;
			_regen = prevRegen;
			#end
			return null;
		}
		
		#if flash
		textField.scrollV = cacheScrollV;
		_regen = prevRegen;
		#end
		
		return boundaries;
	}
	
	function getCharIndexOnDifferentLine(charIndex:Int, lineIndex:Int):Int
	{
		if (charIndex < 0 || charIndex > text.length)
			return -1;
		if (lineIndex < 0 || lineIndex > textField.numLines - 1)
			return -1;
			
		var x = 0.0;
		var charBoundaries = getCharBoundaries(charIndex - 1);
		if (charBoundaries != null)
		{
			x = charBoundaries.right;
		}
		else
		{
			x = GUTTER;
		}
		
		var y = GUTTER + getLineY(lineIndex) + textField.getLineMetrics(lineIndex).height / 2;
		
		return getCharAtPosition(x, y);
	}
	
	function getLineIndexOfChar(char:Int):Int
	{
		// On Flash, if the character is equal to the end of the text, it returns -1 as the line.
		// We have to fix it manually.
		return (char == text.length) ? textField.numLines - 1 : textField.getLineIndexOfChar(char);
	}
	
	/**
	 * NOTE: This does not include the vertical gutter on top of the text field.
	 */
	function getLineY(line:Int):Float
	{
		var scrollY = 0.0;
		for (i in 0...line)
		{
			scrollY += textField.getLineMetrics(i).height;
		}
		return scrollY;
	}

	function getScrollVOffset():Float
	{
		return getLineY(scrollV - 1);
	}

	function isCaretLineVisible():Bool
	{
		// `getLineIndexOfChar()` will return -1 if text is empty, but we still want the caret to show up
		if (text.length == 0)
			return true;

		var line = getLineIndexOfChar(_caretIndex);
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
				var lineIndex = getLineIndexOfChar(_caretIndex);
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
				var lineIndex = getLineIndexOfChar(_caretIndex);
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
				_caretIndex = textField.getLineOffset(getLineIndexOfChar(_caretIndex));
				
				if (!shiftKey)
				{
					_selectionIndex = _caretIndex;
				}
				setSelection(_selectionIndex, _caretIndex);
			case LINE_END:
				var lineIndex = getLineIndexOfChar(_caretIndex);
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
				var lineIndex = getLineIndexOfChar(_caretIndex);
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
				var lineIndex = getLineIndexOfChar(_caretIndex);
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

	function onChange(action:FlxInputTextAction):Void
	{
		if (callback != null)
		{
			callback(text, action);
			if (action == INPUT_ACTION || action == BACKSPACE_ACTION || action == DELETE_ACTION)
			{
				callback(text, CHANGE_ACTION);
			}
		}
	}

	function regenBackground():Void
	{
		if (!background)
			return;
			
		if (fieldBorderThickness > 0)
		{
			_fieldBorderSprite.makeGraphic(Std.int(fieldWidth) + (fieldBorderThickness * 2), Std.int(fieldHeight) + (fieldBorderThickness * 2),
				fieldBorderColor);
			_fieldBorderSprite.visible = true;
		}
		else
		{
			_fieldBorderSprite.visible = false;
		}
		
		if (backgroundColor.alpha > 0)
		{
			_backgroundSprite.makeGraphic(Std.int(fieldWidth), Std.int(fieldHeight), backgroundColor);
			_backgroundSprite.visible = true;
		}
		else
		{
			_backgroundSprite.visible = false;
		}
		
		updateBackgroundPosition();
		_regenBackground = false;
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
				if (editable && multiline)
				{
					addText("\n");
				}
				else
				{
					stopCaretTimer();
					startCaretTimer();
				}
				onChange(ENTER_ACTION);
			case DELETE_LEFT:
				if (!editable)
					return;

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
				else
				{
					stopCaretTimer();
					startCaretTimer();
				}
			case DELETE_RIGHT:
				if (!editable)
					return;

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
				else
				{
					stopCaretTimer();
					startCaretTimer();
				}
			case COPY:
				if (_caretIndex != _selectionIndex && !passwordMode)
				{
					Clipboard.text = text.substring(_caretIndex, _selectionIndex);
				}
			case CUT:
				if (editable && _caretIndex != _selectionIndex && !passwordMode)
				{
					Clipboard.text = text.substring(_caretIndex, _selectionIndex);
					
					replaceSelectedText("");
				}
			case PASTE:
				if (editable && Clipboard.text != null)
				{
					addText(Clipboard.text);
				}
			case SELECT_ALL:
				_selectionIndex = 0;
				_caretIndex = text.length;
				setSelection(_selectionIndex, _caretIndex);
		}
	}

	function startCaretTimer():Void
	{
		_caretTimer.cancel();
		
		_caretFlash = !_caretFlash;
		updateCaretVisibility();
		_caretTimer.start(0.6, function(tmr)
		{
			startCaretTimer();
		});
	}
	
	function stopCaretTimer():Void
	{
		_caretTimer.cancel();
		
		if (_caretFlash)
		{
			_caretFlash = false;
			updateCaretVisibility();
		}
	}

	function updateBackgroundPosition():Void
	{
		if (!background)
			return;
			
		_fieldBorderSprite.setPosition(x - fieldBorderThickness, y - fieldBorderThickness);
		_backgroundSprite.setPosition(x, y);
	}
	
	function updateCaretPosition():Void
	{
		if (textField == null)
			return;
			
		if (text.length == 0)
		{
			_caret.setPosition(x + getCaretOffsetX(), y + GUTTER);
		}
		else
		{
			var lineY = GUTTER + getLineY(getLineIndexOfChar(_caretIndex));
			var boundaries = getCharBoundaries(_caretIndex - 1);
			if (boundaries != null)
			{
				_caret.setPosition(x + boundaries.right - scrollH, y + lineY - getScrollVOffset());
			}
			else
			{
				boundaries = getCharBoundaries(_caretIndex);
				if (boundaries != null)
				{
					_caret.setPosition(x + boundaries.x - scrollH, y + lineY - getScrollVOffset());
				}
				else // end of line
				{
					_caret.setPosition(x + getCaretOffsetX(), y + GUTTER + lineY - getScrollVOffset());
				}
			}
		}
		
		_caret.clipRect = _caret.getHitbox(_caret.clipRect).clipTo(FlxRect.weak(x, y, width, height)).offset(-_caret.x, -_caret.y);
	}
	
	function updateCaretSize():Void
	{
		if (_caret == null)
			return;
			
		_caret.setGraphicSize(caretWidth, textField.getLineMetrics(0).height);
		_caret.updateHitbox();
	}
	
	function updateCaretVisibility():Void
	{
		_caret.visible = (_caretFlash && _selectionIndex == _caretIndex && isCaretLineVisible());
	}
	
	#if flash
	function updateScrollH():Void
	{
		if (textField.textWidth <= width - (GUTTER * 2))
		{
			scrollH = 0;
			return;
		}
		
		var tempScrollH = scrollH;
		if (_caretIndex == 0 || textField.getLineOffset(getLineIndexOfChar(_caretIndex)) == _caretIndex)
		{
			tempScrollH = 0;
		}
		else
		{
			var caret:Rectangle = null;
			if (_caretIndex < text.length)
			{
				caret = getCharBoundaries(_caretIndex);
			}
			if (caret == null)
			{
				caret = getCharBoundaries(_caretIndex - 1);
				caret.x += caret.width;
			}
			
			while (caret.x < tempScrollH && tempScrollH > 0)
			{
				tempScrollH -= 24;
			}
			while (caret.x > tempScrollH + width - (GUTTER * 2))
			{
				tempScrollH += 24;
			}
		}
		
		if (tempScrollH < 0)
		{
			scrollH = 0;
		}
		else if (tempScrollH > maxScrollH)
		{
			scrollH = maxScrollH;
		}
		else
		{
			scrollH = tempScrollH;
		}
	}
	#end
	
	function updateSelection(keepScroll:Bool = false):Void
	{
		var cacheScrollH = scrollH;
		var cacheScrollV = scrollV;

		textField.setSelection(_selectionIndex, _caretIndex);
		stopCaretTimer();
		startCaretTimer();
		_regen = true;

		if (keepScroll)
		{
			scrollH = cacheScrollH;
			scrollV = cacheScrollV;
		}
		else
		{
			#if flash
			// Horizontal scroll is not automatically set on Flash
			updateScrollH();
			#end
			
			if (scrollH != cacheScrollH || scrollV != cacheScrollV)
			{
				onChange(SCROLL_ACTION);
			}
		}
	}
	
	function updateSelectionBoxes():Void
	{
		if (textField == null)
			return;

		var visibleLines = bottomScrollV - scrollV + 1;
		while (_selectionBoxes.length > visibleLines)
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
		
		var beginLine = getLineIndexOfChar(selectionBeginIndex);
		var endLine = getLineIndexOfChar(selectionEndIndex);
		
		var beginV = scrollV - 1;
		
		for (line in beginV...bottomScrollV)
		{
			var i = line - beginV;
			var box = _selectionBoxes[i];
			if (line >= beginLine && line <= endLine)
			{
				var lineStartIndex = textField.getLineOffset(line);
				var lineEndIndex = lineStartIndex + textField.getLineLength(line);
				
				var startIndex = FlxMath.maxInt(lineStartIndex, selectionBeginIndex);
				var endIndex = FlxMath.minInt(lineEndIndex, selectionEndIndex);
				
				var startBoundaries = getCharBoundaries(startIndex);
				var endBoundaries = getCharBoundaries(endIndex - 1);
				if (endBoundaries == null && endIndex > startIndex) // end of line, try getting the previous character
				{
					endBoundaries = getCharBoundaries(endIndex - 2);
				}
				
				if (startBoundaries != null && endBoundaries != null)
				{
					if (box == null)
					{
						box = _selectionBoxes[i] = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
						box.color = selectionColor;
					}

					var boxRect = FlxRect.get(startBoundaries.x - scrollH, GUTTER + getLineY(line) - getScrollVOffset(),
						endBoundaries.right - startBoundaries.x,
						startBoundaries.height);
					boxRect.clipTo(FlxRect.weak(0, 0, width, height)); // clip the selection box inside the text sprite
					
					box.setPosition(x + boxRect.x, y + boxRect.y);
					if (boxRect.width > 0 && boxRect.height > 0)
						box.setGraphicSize(boxRect.width, boxRect.height);
					else
						box.scale.set();
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
		updateCaretVisibility();
		updateCaretPosition();
		updateSelectionBoxes();
	}

	function updateSpritePositions():Void
	{
		updateBackgroundPosition();
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
		}
		else if (FlxG.mouse.justReleased)
		{
			_lastClickTime = 0;
		}

		if (checkPointerOverlap(FlxG.mouse))
		{
			if (FlxG.mouse.justPressed && selectable)
			{
				_mouseDown = true;
				updatePointerPress(FlxG.mouse);
			}
			
			if (FlxG.mouse.wheel != 0)
			{
				var cacheScrollV = scrollV;
				scrollV = FlxMath.minInt(scrollV - FlxG.mouse.wheel, maxScrollV);
				if (scrollV != cacheScrollV)
				{
					onChange(SCROLL_ACTION);
				}
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
		_caretIndex = getCharAtPosition(relativePos.x + scrollH, relativePos.y + getScrollVOffset());
		_selectionIndex = _caretIndex;
		updateSelection(true);
		
		relativePos.put();
	}

	function updatePointerDrag(pointer:FlxPointer, elapsed:Float)
	{
		var relativePos = getRelativePosition(pointer);
		var cacheScrollH = scrollH;
		var cacheScrollV = scrollV;
		
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

		if (scrollH != cacheScrollH || scrollV != cacheScrollV)
		{
			onChange(SCROLL_ACTION);
		}
	}
	
	function updatePointerMove(pointer:FlxPointer):Void
	{
		if (_selectionIndex < 0)
			return;
			
		var relativePos = getRelativePosition(pointer);
		
		var char = getCharAtPosition(relativePos.x + scrollH, relativePos.y + getScrollVOffset());
		if (char != _caretIndex)
		{
			_caretIndex = char;
			updateSelection(true);
		}

		relativePos.put();
	}
	
	function updatePointerRelease(pointer:FlxPointer):Void
	{
		if (!hasFocus)
			return;
			
		var relativePos = getRelativePosition(pointer);
		
		var upPos = getCharAtPosition(relativePos.x + scrollH, relativePos.y + getScrollVOffset());
		var leftPos = FlxMath.minInt(_selectionIndex, upPos);
		var rightPos = FlxMath.maxInt(_selectionIndex, upPos);
		
		_selectionIndex = leftPos;
		_caretIndex = rightPos;
		updateSelection(true);

		if (hasFocus)
		{
			stopCaretTimer();
			startCaretTimer();
		}

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
	
	override function set_bold(value:Bool):Bool
	{
		if (bold != value)
		{
			super.set_bold(value);
			updateCaretSize();
		}
		
		return value;
	}
	
	override function set_color(value:FlxColor):FlxColor
	{
		if (color != value)
		{
			super.set_color(value);
			caretColor = value;
		}
		
		return value;
	}
	override function set_fieldHeight(value:Float):Float
	{
		if (fieldHeight != value)
		{
			super.set_fieldHeight(value);
			_regenBackground = true;
		}
		
		return value;
	}
	
	override function set_fieldWidth(value:Float):Float
	{
		if (fieldWidth != value)
		{
			super.set_fieldWidth(value);
			_regenBackground = true;
		}
		
		return value;
	}
	
	override function set_font(value:String):String
	{
		if (font != value)
		{
			super.set_font(value);
			updateCaretSize();
		}
		
		return value;
	}
	
	override function set_italic(value:Bool):Bool
	{
		if (italic != value)
		{
			super.set_italic(value);
			updateCaretSize();
		}
		
		return value;
	}
	
	override function set_size(value:Int):Int
	{
		if (size != value)
		{
			super.set_size(value);
			updateCaretSize();
		}
		
		return value;
	}
	
	override function set_systemFont(value:String):String
	{
		if (systemFont != value)
		{
			super.set_systemFont(value);
			updateCaretSize();
		}
		
		return value;
	}
	
	override function set_text(value:String):String
	{
		if (text != value)
		{
			super.set_text(value);
			
			if (textField != null)
			{
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
		}
		
		return value;
	}

	override function set_x(value:Float)
	{
		if (x != value)
		{
			super.set_x(value);
			updateSpritePositions();
		}
		
		return value;
	}
	
	override function set_y(value:Float)
	{
		if (y != value)
		{
			super.set_y(value);
			updateSpritePositions();
		}
		
		return value;
	}
	
	function set_background(value:Bool):Bool
	{
		if (background != value)
		{
			background = value;
			
			if (background)
			{
				if (_backgroundSprite == null)
					_backgroundSprite = new FlxSprite();
				if (_fieldBorderSprite == null)
					_fieldBorderSprite = new FlxSprite();
					
				_regenBackground = true;
			}
			else
			{
				_backgroundSprite = FlxDestroyUtil.destroy(_backgroundSprite);
				_fieldBorderSprite = FlxDestroyUtil.destroy(_fieldBorderSprite);
			}
		}
		
		return value;
	}
	
	function set_backgroundColor(value:FlxColor):FlxColor
	{
		if (backgroundColor != value)
		{
			backgroundColor = value;
			_regenBackground = true;
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
		if (value < 0)
			value = 0;
		if (value > text.length)
			value = text.length;
		if (_caretIndex != value)
		{
			_caretIndex = value;
			setSelection(_caretIndex, _caretIndex);
		}

		return value;
	}
	
	function set_caretWidth(value:Int):Int
	{
		if (value < 1)
			value = 1;
		if (caretWidth != value)
		{
			caretWidth = value;
			updateCaretSize();
		}

		return value;
	}
	
	function set_customFilterPattern(value:EReg):EReg
	{
		if (customFilterPattern != value)
		{
			customFilterPattern = value;
			if (filterMode == CUSTOM_FILTER)
			{
				text = filterText(text);
			}
		}
		
		return value;
	}

	function set_fieldBorderColor(value:FlxColor):FlxColor
	{
		if (fieldBorderColor != value)
		{
			fieldBorderColor = value;
			_regenBackground = true;
		}
		
		return value;
	}
	
	function set_fieldBorderThickness(value:Int):Int
	{
		if (value < 0)
			value = 0;
		if (fieldBorderThickness != value)
		{
			fieldBorderThickness = value;
			_regenBackground = true;
		}
		
		return value;
	}
	
	function set_filterMode(value:FlxInputTextFilterMode):FlxInputTextFilterMode
	{
		if (filterMode != value)
		{
			filterMode = value;
			text = filterText(text);
		}
		
		return value;
	}
	
	function set_forceCase(value:FlxInputTextCase):FlxInputTextCase
	{
		if (forceCase != value)
		{
			forceCase = value;
			text = filterText(text);
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
					updateSelection(true);
				}
				
				stopCaretTimer();
				startCaretTimer();

				if (focusGained != null)
					focusGained();
			}
			else if (FlxG.inputText.focus == this)
			{
				FlxG.inputText.focus = null;
				
				if (_selectionIndex != _caretIndex)
				{
					_selectionIndex = _caretIndex;
					updateSelection(true);
				}
				
				stopCaretTimer();
				
				if (focusLost != null)
					focusLost();
			}
		}

		return value;
	}
	
	function set_maxLength(value:Int):Int
	{
		if (value < 0)
			value = 0;
		if (maxLength != value)
		{
			maxLength = value;
			text = filterText(text);
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
			if (multiline)
			{
				_autoHeight = false;
			}
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

	function set_useSelectedTextFormat(value:Bool):Bool
	{
		if (useSelectedTextFormat != value)
		{
			useSelectedTextFormat = value;
			_regen = true;
		}
		
		return value;
	}
}

enum abstract FlxInputTextAction(String) from String to String
{
	var CHANGE_ACTION = "change";
	var INPUT_ACTION = "input";
	var BACKSPACE_ACTION = "backspace";
	var DELETE_ACTION = "delete";
	var ENTER_ACTION = "enter";
	var SCROLL_ACTION = "scroll";
}

enum abstract FlxInputTextCase(Int) from Int to Int
{
	var ALL_CASES = 0;
	var UPPER_CASE = 1;
	var LOWER_CASE = 2;
}

enum abstract FlxInputTextFilterMode(Int) from Int to Int
{
	var NO_FILTER = 0;
	var ONLY_ALPHA = 1;
	var ONLY_NUMERIC = 2;
	var ONLY_ALPHANUMERIC = 3;
	var CUSTOM_FILTER = 4;
}
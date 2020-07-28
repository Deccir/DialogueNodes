tool
extends Control

# Nodes
var StartNode = preload("res://addons/dialogue_nodes/nodes/StartNode.tscn")
var DialogueNode = preload("res://addons/dialogue_nodes/nodes/DialogueNode.tscn")
var EndNode = preload("res://addons/dialogue_nodes/nodes/EndNode.tscn")
var CommentNode = preload("res://addons/dialogue_nodes/nodes/CommentNode.tscn")

var start  # The start node. Only one allowed in a graph.
var selected  # The selected node.
var currentNode # The demo node to display
var demoDict # The dictionary of dialogue tree for demo
var demoIndex # The dict index of current dialogue

var lastSpeaker = '' # The last speaker from the last dialogue node changed
var lastPosition = Vector2.ZERO # The position of the last moved node
var lastOffset = 0 # Offset index

onready var fileMenu = $Main/ToolBar/FileMenu
onready var addMenu = $Main/ToolBar/AddMenu
onready var runMenu = $Main/ToolBar/RunMenu
onready var graph = $Main/Graph
onready var demo = $Demo


func _ready():
	start = null

	fileMenu.get_popup().connect("id_pressed", self, '_on_file_menu_pressed')
	addMenu.get_popup().connect("id_pressed", self, '_on_add_menu_pressed')
	runMenu.get_popup().connect("id_pressed", self, '_on_run_menu_pressed')


func addNode(node):
	var nodeInstance = node.instance()
	
	nodeInstance.connect('close_request', self, '_on_node_close_request', [nodeInstance])
	nodeInstance.connect('dragged', self, '_on_node_dragged')
	nodeInstance.name = '1'
	graph.add_child(nodeInstance, true)
	nodeInstance.title += ' - ' + nodeInstance.name
	nodeInstance.offset = lastPosition + Vector2(20, 20) * lastOffset
	
	lastOffset += 1
	
	if node == StartNode:
		if start == null:
			start = nodeInstance
			addMenu.get_popup().set_item_disabled(0, true)
	elif node == DialogueNode:
		nodeInstance.connect('speakerChanged', self, '_on_speaker_changed')
		nodeInstance.setSpeaker(lastSpeaker)


func removeNode(node):
	# Clear hanging connections
	removeAllConnections(node.name, node.name)

	# Enable menu options if disabled
	if node == start:
		start = null
		addMenu.get_popup().set_item_disabled(0, false)

	node.queue_free()


func removeInvalidConnections(from, from_slot= -1, to= null, to_slot= -1):
	for connection in graph.get_connection_list():
		if connection['from'] == from:
			if connection['to'] != to and connection['from_port'] == from_slot:
				graph.disconnect_node(
					connection['from'], connection['from_port'], connection['to'], connection['to_port']
				)


func removeAllConnections(from, to):
	for connection in graph.get_connection_list():
		if connection['from'] == from or connection['to'] == to:
			graph.disconnect_node(
				connection['from'], connection['from_port'], connection['to'], connection['to_port']
			)


func clearGraph():
	for child in graph.get_children():
		if child is GraphNode:
			removeNode(child)
	start = null
	selected = null


func getNextNode(nodeName):
	var connections = []
	var nextNodeNames = []
	for connection in graph.get_connection_list():
		if connection['from'] == nodeName:
			connections.append(connection)
	connections.sort_custom(self, 'sortBySlot')
	
	for connection in connections:
		nextNodeNames.append(connection['to'])
	
	return nextNodeNames

func sortBySlot(a, b):
	return a['from_port'] < b['from_port']


func isTreeComplete():
	return (start != null and getNextNode(start.name).size() > 0)


func startDemo():
	if isTreeComplete():
		demoDict = toDict(start.name)
		if demoDict != null:
			demoIndex = demoDict['Start']
			updateDemo()
	demo.popup_centered()


func updateDemo():
	# demoDict demoIndex
	if demoDict[demoIndex] is String and (demoDict.has(demoIndex) and demoDict[demoIndex] == 'End'):
		demo.hide()
	else:
		var currentDialogue = demoDict[demoIndex]
		var options = demo.get_node("Options")
		
		demo.get_node("Speaker").text = currentDialogue['Speaker']
		demo.get_node("Dialogue").bbcode_text = currentDialogue['Dialogue']
		
		#Reset options
		for i in range(1, options.get_child_count()):
			var option = options.get_child(i)
			option.text = ''
			option.disabled = true
			option.hide()
		
		for i in range(currentDialogue['Options'].size()):
			var option = options.get_child(i)
			var demoOption = currentDialogue["Options"][str(i)]
			
			option.text = demoOption['Text']
			option.disabled = false
			option.show()
			
			# Disconnect previous connections
			if options.get_child(i).is_connected('pressed', self, '_on_option_pressed'):
				options.get_child(i).disconnect('pressed', self, '_on_option_pressed')
			# Add updated connection
			options.get_child(i).connect('pressed', self, '_on_option_pressed', [demoOption['Link']])


func toDict(nodeName, dict= {}):
	# If tree is complete, i.e. start -> node/s -> end
	if isTreeComplete():
		currentNode = graph.get_node(nodeName)
		
		match currentNode.getType():
			'Start':
				# First after start
				var firstNode = getNextNode(nodeName)[0]
				dict['Start'] = firstNode
				
				return toDict(firstNode, dict)
				
			'Dialogue':
				var dialogue = {}
				var options = {}
				var optionNames = currentNode.getOptionNames()
				var optionLinks = getNextNode(currentNode.name)
				
				if optionLinks.size() == 0:
					dict[nodeName] = 'End'
					print('Tree contains loose ends aborting.')
					return null
				else:
					options['0'] = {
						'Text': 'Next',
						'Link': optionLinks[0]
						}
				
				for i in range(optionNames.size()):
					var option = {}
					
					option['Text'] = optionNames[i]
					option['Link'] = optionLinks[min(i, optionLinks.size()-1)]
					
					options[str(i)] = option
				
				dialogue['Speaker'] = currentNode.getSpeaker()
				dialogue['Dialogue'] = currentNode.getDialogue()
				dialogue['Options'] = options
				dict[nodeName] = dialogue
				
				for next in optionLinks:
					if not dict.has(next):
						var newDict = toDict(next, dict)
						if newDict != null:
							dict = newDict
				
				return dict
				
			'End':
				dict[nodeName] = 'End'
				
				print('Finished converting tree to dictionary.')
				
				return dict
				
			'Comment':
				return dict
				
			_:
				print('Unknown type. Ending traversal of this branch')
				
				return dict


func _on_file_menu_pressed(id):
	match id:
		0:
			clearGraph()
		1:
			$SaveDialog.popup_centered()
		2:
			clearGraph()


func _on_add_menu_pressed(id):
	match id:
		0:
			addNode(StartNode)
		1:
			addNode(DialogueNode)
		2:
			addNode(EndNode)
		3:
			addNode(CommentNode)


func _on_run_menu_pressed(id):
	match id:
		0:
			startDemo()
		1:
			$LoadDialog.popup_centered()


func _on_node_close_request(node):
	removeNode(node)


func _on_node_dragged(from, to):
	lastPosition = to
	lastOffset = 1

func _on_node_connection_request(from, from_slot, to, to_slot):
	if from != to:
		# Remove previous connections
		removeInvalidConnections(from, from_slot)
		# Make new connection
		graph.connect_node(from, from_slot, to, to_slot)


func _on_node_disconnection_request(from, from_slot, to, to_slot):
	graph.disconnect_node(from, from_slot, to, to_slot)


func _on_delete_nodes_request():
	if selected != null:
		removeNode(selected)
		selected = null


func _on_node_selected(node):
	selected = node
	lastPosition = node.offset


func _on_test_pressed():
	startDemo()


func _on_option_pressed(nextNode):
	demoIndex = nextNode
	updateDemo()


func _on_speaker_changed(newSpeaker):
	lastSpeaker = newSpeaker


func _on_SaveDialog_file_selected(path):
	var dict = toDict(start.name)
	var file = File.new()
	file.open(path, File.WRITE)
	file.store_line(to_json(dict))
	file.close()


func _on_LoadDemo_file_selected(path):
	var file = File.new()
	var output
	
	file.open(path, File.READ)
	output = parse_json(file.get_as_text())
	if typeof(output) == TYPE_DICTIONARY:
		demoDict = output
		demoIndex = output['Start']
		updateDemo()
		demo.popup_centered()

---
title: "Milestone 2: Controlling Kytos Topology Metadata Through File Uploads"
...

# Introduction

A feature the CIARA team would like to be added to Kytos Topology,
is the ability to submit a json file specifying metadata of the components of the topology. This feature will be used to provide metadata for pathfinder and other NApps.
This report covers the changes I've made to the Toplogy module, in order to achieve this end.

# Planning / Implementation

Before I could begin to write code,
I first created a plan for how I would implement the new method.
It would first need to be exposed as a REST endpoint,
be able to retrieve the file from the the API call,
read and decode the file, then finally store the input.
Exposing the new method as a REST endpoint was trivial.
Kytos uses the flask framework to handle REST API calls,
so I annotated the new method I was making with `@rest()` to expose it as a REST endpoint.
After this initial bout of planning, I created the following skeleton method, called `add_topology_metadata`.

```python
import json
from flask import request, jsonify
from kytos.core import rest, KytosNApp
...
class Main(KytosNApp):
    ...
    @rest('v3/metadata', methods=['POST'])
    def add_topology_metadata(self):
        """Accept a file, and use its contents for the metadata of the topology."""
        ### Retrieve file from request
        ...
        ### Read and Decode the file
        ...
        ### Validate and Store results to storehouse
        ...
        ### return confirmation that the receive file was processed correctly
        return jsonify('Operation successful'), 201
    ...
```

## Retrieving the Input File

Reading data from requests in flask is done through the `request` context.
One of the properties of the `request` context is `files`, which contains all files uploaded with the request. `add_topology_metadata` checks this property for the field `'file'` in the
`file` property of the request context, and then checks that it isn't empty.

```python
        ...
        ### Retrieve file from request
        # File with the input field name as 'file'
        # Check if there is a 'file' field
        if 'file' not in request.files:
            return jsonify('Missing field: \'file\''), 400
        
        # Get file from field
        inputFile = request.files['file']

        # Check if field was empty
        if inputFile.filename is '':
            return jsonify('Empty field: \'file\''), 400
        ...
```

## Reading and Decoding the Input File

With the `inputFile`, received, and confirmed not to be empty,
read operations can begin.
The type used to represent files in flask includes an input stream,
which the whole file can be read from.
This input stream can then be directly converted as json into a python object
using the python json library.

```python
        ...
        ### Read and Decode the file
        # get the input stream
        inputStream = file.stream
        # Convert stream to python data structure
        try:
            inputObject = json.load(inputStream)
        except json.JSONDecodeError:
            return jsonify('Could not decode file as json'), 400
        ...
```

## Defining the Input

I would need to know how the data would be structured,
before I could write the code for storing it.
To do so, I created the following template.

```json
{
    "switches": [
        {
            "dpid": "00:00:00:00:00:01", //Primary key, required
            "metadata": { // Metadata Changes, optional
                "long": 0.3,
                "lat":0.1
            },
            "interfaces": [
                {
                    "port":1, // Partial key, required
                    "metadata": {} // Metadata Changes, optional
                }
            ]
        },
        {
            "dpid": "00:00:00:00:00:02",
            "interfaces": [
                {
                    "port":1
                }
            ]
        }
    ],
    "links": [
        {
            "id":"00:00:00:00:00:01:1:00:00:00:00:00:02:2", // Primary key, required
            "metadata":{ // Metadata Changes, optional
                "speed":100
            }
        }
    ]
}
```

## Storing the Contents of the Input

The system at this point now has a representation of the data from
the input file which can easily be worked with.
All that remains is for the system to store the data.

Topology uses two seperate representations of the data for the representation of the network; one volatile, in memory; the other persistent, accessible through the Storehouse NApp. To update both, the volatile representation needs to be updated, then afterwards an event to event to the Storehouse is raised to update the persistent representation.

```python
        ...
        ### Validate and Store results to storehouse
        # Check it its a dict, discard if not
        if not isinstance(inputObject, dict):
            return jsonify('json produced incorrect type'), 400
        
        # Get list of switches
        switches = inputObject.get('switches',None)
        # skip iterating through switches if invalid type
        if isinstance(switches, list):
            for switch_data in switches:
                # skip element if invalid
                if not isinstance(switch_data, dict):
                    continue
                # Get dpid and switch with that dpid
                try:
                    dpid = switch_data['dpid']
                    switch = self.controller.switches[dpid]
                # Skip if getting the dpid or the switch fails
                except KeyError: 
                    continue

                # get metadata
                switch_metadata = switch_data.get('metadata', None)
                # Confirm it is of the right types
                if isinstance(switch_metadata, dict):
                    # Update volatile
                    switch.extend_metadata(switch_metadata)
                    # Update Persistent
                    self.notify_metadata_changes(switch,'added')
                
                # get list of interfaces
                interfaces = switch_data.get('interfaces', None)
                # skip iterating through interfaces if invalid type
                if isinstance(interfaces, list):
                    for interface_data in interfaces:
                        # skip element if invalid
                        if not isinstance(interface_data, dict):
                            continue
                        # Get port and interface at that port
                        try:
                            port = interface_data['port']
                            interface = switch.interfaces[port]
                        # Skip if getting the port or interface fails
                        except KeyError: 
                            continue
                        
                        # get metadata
                        interface_metadata = interface_data.get('metadata', None)
                        # Confirm it is of the right types
                        if isinstance(interface_metadata, dict):
                            # Update volatile
                            interface.extend_metadata(interface_metadata)
                            # Update Persistent
                            self.notify_metadata_changes(interface,'added')

        # Get list of links
        links = inputObject.get('links',None)
        # skip iterating through switches if invalid type
        if isinstance(links, list):
            for link_data in links:
                # skip element if invalid
                if not isinstance(link_data, dict):
                    continue
                # Get id and link with that id
                try:
                    link_id = link_data['id']
                    link = self.links[link_id]
                # Skip if getting the id or the link fails
                except KeyError: 
                    continue

                # get metadata
                link_metadata = link_data.get('metadata', None)
                # Confirm it is of the right types
                if isinstance(link_metadata, dict):
                    # Update volatile
                    link.extend_metadata(link_metadata)
                    # Update Persistent
                    self.notify_metadata_changes(link,'added')
        ...
```

## Additional Notes on the Implementation

This section covers a few changes that I think should be made to the code,
but didn't implement. 

The process of updating the metadata for any component of the topology is identical, regardless is the component is a switch, link, or interface.
This process could be consolidated into a single method, removing the need to have the same process written multiple times.
Here's an example of what this could look like.

```python
# Instead of having to write this

    # get metadata
    switch_metadata = switch_data.get('metadata', None)
    # Confirm it is of the right types
    if isinstance(switch_metadata, dict):
        # Update volatile
        switch.extend_metadata(switch_metadata)
        # Update Persistent
        self.notify_metadata_changes(switch,'added')

# We could instead write this method

    def update_entity(self, entity, metadata):
        entity.extend_metadata(metadata)
        self.notify_metadata_changes(entity,'added')

# Which allows us to rewrite the first bit of code as

    # get metadata
    switch_metadata = switch_data.get('metadata', {})
    self.update_entity(switch, switch_metadata)
```

The method, as I've implemented, has a large chunk of the code dedicated to input validation.
While not strictly necessary to perform, it prevents the system from spitting out server errors without any explanation.
The validation could either be removed, or replaced with a check against a schema. Checking against a schema would require introducing additional dependencies.

# Testing

This section covers testing of the method `add_topology_metadata`. For testing, a new method called `test_add_topology_metadata` was added to the unit test driver in `tests/unit/test_main.py`.

## Mocks and Test Setup

No matter the process used to update the metadata, they all result in the
same set of calls per entity. First a call to `extend_metadata` on the entity,
then a call to `notify_metadata_changes`. To confirm that my implementation
is working, I used mocks to assert that these calls are executed.
The `notify_metadata_changes` method was mocked, as well as each individual entity
I would be using in topology for testing. The following is the setup code for
the tests:

```python
    @patch('napps.kytos.topology.main.Main.notify_metadata_changes')
    def test_add_topology_metadata(self, mock_metadata_changes):
        """Test add_topology_metadata"""
        topology_init_state = {...} # Test setup
        # Transfomr topology_init_state into test setup
        mock_switches = {}
        for switch_data in topology_init_state['switches']:
            mock_switch = get_switch_mock(switch_data['dpid'])
            mock_switch.interfaces = {}
            for interface_data in switch_data['interfaces']:
                mock_interface = get_interface_mock(interface_data['name'], interface_data['port'], mock_switch)
                mock_switch.interfaces[interface_data['port']] = mock_interface
            mock_switches[switch_data['dpid']] = mock_switch

        mock_links = {}
        for link_data in topology_init_state['links']:
            mock_link = MagicMock(Link)
            mock_link.id = link_data['id']
            mock_links[link_data['id']] = mock_link

        self.napp.controller.switches = mock_switches
        self.napp.links = mock_links
        ...
```

The initial state of the system is determined by the topology_init_state variable,
which will be translated into a set of mock entities for testing. The following is the value used for the init state variable in the tests:

```python
topology_init_state = {
    'switches':
    [
        {
            'dpid':'00:00:00:00:00:00:00:01',
            'interfaces':[
                {'port':1,'name':'eth0'}
            ]
        },
        {
            'dpid':'00:00:00:00:00:00:00:02',
            'interfaces':[
                {'port':1,'name':'eth0'},
                {'port':2,'name':'eth1'}
            ]
        },
        {
            'dpid':'00:00:00:00:00:00:00:03',
            'interfaces':[
                {'port':1,'name':'eth0'}
            ]
        }
    ],
    'links':
    [
        {
            'id': '00:00:00:00:00:00:00:01:1:00:00:00:00:00:00:00:02:2'
        }
    ]
}
```

## Test Inputs and Execution

To execute a call to `add_topology_metadata`

Executing a call to `add_topology_metadata` requires passing data through the Flask request context. Flask has a test client, which allows for making calls as if they where a normal http request. The test client can be accessed with a call to `kytos.lib.helpers.get_test_client`.
With the test client calls to the `add_topology_metadata` method can be made through the following code:

```python
        ...
        api = get_test_client(self.napp.controller, self.napp)
        url = f'{self.server_name_url}/v3/metadata'
        response = api.post(url, data = {'file': (file, fileName)})
        ...
```

All that would be needed to change for each test case is the file being passed to the method, as well as the name of the file.

## Tests Cases

The following section covers the test cases used to test `add_topology_metadata`.

### Test 1: Valid Input

This tests inputing a valid json file, and checks that all expected entities have been updated.

#### Input

The input specifies entities that do and do not exist to be udpated. Also included are some entries that specify no change to be made at all.
The following specifies the input for the test:

```python
        ...
        topology_update = {
            'switches':
            [
                {
                    'dpid':'00:00:00:00:00:00:00:01',
                    'metadata':{'color':'red','char':'A'},
                    'interfaces':[
                        {'port':1,'name':'eth0'}
                    ]
                },
                {
                    'dpid':'00:00:00:00:00:00:00:02',
                    'metadata':{'color':'green','char':'A'},
                    'interfaces':[
                        {'port':1,'name':'eth0'},
                        {'port':2,'name':'eth1','metadata':{'color':'blue'}}
                    ]
                },
                {
                    'dpid':'00:00:00:00:00:00:00:03',
                    'metadata':{'color':'blue','char':'A'},
                    'interfaces':[
                        {'port':1,'name':'eth0','metadata':{'color':'pink'}}
                    ]
                },
                {
                    'dpid':'00:00:00:00:00:00:00:03',
                    'metadata':{'color':'blue','char':'A'},
                    'interfaces':[
                        {'port':1,'name':'eth0','metadata':{'color':'green'}}
                    ]
                }
            ],
            'links':
            [
                {
                    'id': '00:00:00:00:00:00:00:01:1:00:00:00:00:00:00:00:02:2',
                    'metadata': {'color': 'purple'}
                }
            ]
        }
        file = BytesIO(json.dumps(topology_update).encode())
        fileName = 'file.json'
        response = api.post(url, data = {'file': (file, fileName)})
        ...
```

#### Expected Output

The expected output for this test is that the http status code is `201` and all entities
specified to have their metadata updated are updated, if they exist.
This is checked by the following code:

```python
        ...
        self.assertEqual(response.status_code, 201, response.data)
        for switch_update in topology_update['switches']:
            mock_entity = mock_switches.get(switch_update['dpid'], None)
            if mock_entity is None:
                continue
            new_metadata = switch_update.get('metadata', None)
            if new_metadata is not None:
                mock_entity.extend_metadata.assert_any_call(new_metadata)
                mock_metadata_changes.assert_any_call(mock_entity, 'added')
            for interface in switch_update['interfaces']:
                mock_entity = mock_switches.get(switch_update['dpid'], None)
                if mock_entity is None:
                    continue
                new_metadata = switch_update.get('metadata', None)
                if new_metadata is not None:
                    mock_entity.extend_metadata.assert_any_call(new_metadata)
                    mock_metadata_changes.assert_any_call(mock_entity, 'added')
        for link_update in topology_update['links']:
            mock_entity = mock_links.get(link_update['id'], None)
            if mock_entity is None:
                continue
            new_metadata = link_update.get('metadata', None)
            if new_metadata is not None:
                mock_entity.extend_metadata.assert_any_call(new_metadata)
                mock_metadata_changes.assert_any_call(mock_entity, 'added')
        ...
```

### Test 2: Invalid json Type Input

This tests inputing a valid json file, using an invalid json type, and checks that the returned status code is the appropriate error code.

#### Input

The input is a file containing valid json formatted text, but the root object is not a
java script object.
The following specifies the input for the test:

```python
        ...
        # Invalid json data type
        file = BytesIO(json.dumps("Hello!").encode())
        fileName = 'file.json'
        response = api.post(url, data = {'file': (file, fileName)})
        ...
```

#### Expected Output

The expected output for this test is that the http status code is `400`.
This is checked by the following code:

```python
        ...
        self.assertEqual(response.status_code, 400, response.data)
        ...
```

### Test 3: Invalid Input Type

This tests inputing a invalid json file, and checks that the returned status code is the appropriate error code.

#### Input

The input is raw text, not formated into a json formt.
The following specifies the input for the test:

```python
        ...
        # Not a json 
        file = BytesIO("Hello!".encode())
        fileName = 'file.json'
        response = api.post(url, data = {'file': (file, fileName)})
        ...
```

#### Expected Output

The expected output for this test is that the http status code is `400`.
This is checked by the following code:

```python
        ...
        self.assertEqual(response.status_code, 400, response.data)
        ...
```

### Test 4: No Input Data

This tests not inputing a file, and checks that the returned status code is the appropriate error code.

#### Input

No additional input data is provided.
The following specifies the input for the test:

```python
        ...
        # No Input Data
        response = api.post(url)
        ...
```

#### Expected Output

The expected output for this test is that the http status code is `400`.
This is checked by the following code:

```python
        ...
        self.assertEqual(response.status_code, 400, response.data)
        ...
```

### Test 5: Empty Field

This tests having the input field for the file be empty, and checks that the returned status code is the appropriate error code.

#### Input

The input for the file is set as an empty file, with an empty file name.
The following specifies the input for the test:

```python
        ...
        # Empty field
        file = BytesIO('')
        fileName = ''
        response = api.post(url, data = {'file': (file, fileName)})
        ...
```

#### Expected Output

The expected output for this test is that the http status code is `400`.
This is checked by the following code:

```python
        ...
        self.assertEqual(response.status_code, 400, response.data)
        ...
```

## Test Results

Initial testing produced 1 error.
The error found was that for using an invalid input type,
the code was expecting `JSONDecodeError` rather than `json.JSONDecodeError`.
This was fixed, and afterwards all tests re-run.
The final results of testing are the following:


| Test Case                       | Pass/Fail |
|---------------------------------|-----------|
| Test 1: Valid Input             | Pass      |
| Test 2: Invalid json Type Input | Pass      |
| Test 3: Invalid Input Type      | Pass      |
| Test 4: No Input Data           | Pass      |
| Test 5: Empty Field             | Pass      |


# Updating the UI

To make the new feature accessible to users, a new UI element was in order.
For it, I added a new tab for topology, represented by a map icon.
Within the tab is a file upload form, which a json file can be submitted through.
Due to problems with my understanding of how vue works, I was unable to
display a message indicating the response the server sent after completing
the upload.

# Validating the System

To check that the system worked as intended, I created a network using mininet,
then applied metadata to it.
Modifying the latitude and longitude of switches allowed to visualize changes while testing.

During system validation, I discovered that the function used for updating
the persistent representation of the metadata had a flaw in it, which would
result in the metadata not updating. This is caused by the method not properly passing the proper parameters to the event listener, causing an exception.
I did not fix this issue, as its wasn't a core concern of the project.

# Guides

This following is a set of guides and examples for operating the new feature.


## File Format

To get started, you will need a file appropriately formated. Provided below is an example.

```json
{
    "switches": [
        {
            "dpid": "00:00:00:00:00:00:00:01",
            "metadata": {...},
            "interfaces": [
                {
                    "port": 1,
                    "metadata": {...}
                },
                ...
            ]
        },
        ...
    ],
    "links": [
        {
            "id": "00:00:00:00:00:00:00:01:1:00:00:00:00:00:00:00:02:2",
            "metadata": {...}
        },
        ...
    ]
}
```

## Using the UI to Update the Topology Metadata

This is a step by step covering how to use the UI to update the Topology metadata.

 1. Open up the UI
 2. Open up the Topology tab (represented by a map icon)
 3. Click 'Choose File' and select an appropriate json file
 4. Click upload

Due to issues getting the UI to work properly their no confirmation to the user
that the file has been properly received.

## Using Metadata with Pathfinder

One NApp which benefits from adding metadata to topology is pathfinder. 
Attributes about links which can be used in pathfinding can be specified by adding in metadata.
For the version of pathfinder produced as part of my senior project, the following is an example of metadata that can be attached to links for pathfinding:

```json
{
    "links":[
        {
            "id":"link-id",
            "metadata": {
                "ownership":"Jack", // Owner of the link
                "bandwidth":100, // Speed of the link
                "priority":100, // Level of preference
                "reliability":5, //Reliability of data transmission
                "utilization":12, // Percentage of link capacity used
                "delay":13 // One way delay
            }
        },
        ...
    ]
}
```


# References

The following code has been referenced throughout this doc.

## Topology Source

The produced NApp is a fork of the topology repository at https://github.com/kytos/topology.
The source code for the produced NApp can be found at https://github.com/ktmi/topology/tree/bulk-metadata.

The following is the diff for the source code `a` is `master`, `b` is `bulk-metadata`.

```diff
diff --git a/main.py b/main.py
index 01330b6..c7f5451 100644
--- a/main.py
+++ b/main.py
@@ -2,7 +2,7 @@
 
 Manage the network topology
 """
-import time
+import time, json
 
 from flask import jsonify, request
 
@@ -160,6 +160,113 @@ class Main(KytosNApp):  # pylint: disable=too-many-public-methods
 
         return jsonify('Administrative status restored.'), 200
 
+    @rest('v3/metadata', methods=['POST'])
+    def add_topology_metadata(self):
+
+        ### Retrieve file from request
+        # File with the input field name as 'file'
+        # Check if there is a 'file' field
+        if 'file' not in request.files:
+            return jsonify('Missing field: \'file\''), 400
+        
+        # Get file from field
+        inputFile = request.files['file']
+
+        # Check if field was empty
+        if inputFile.filename is '':
+            return jsonify('Empty field: \'file\''), 400
+        
+        ### Read and Decode the file
+        # get the input stream
+        inputStream = inputFile.stream
+        # Convert stream to python data structure
+        try:
+            inputObject = json.load(inputStream)
+        except json.JSONDecodeError:
+            return jsonify('Could not decode file as json'), 400
+        
+        ### Validate and Store results to storehouse
+        # Check it its a dict, discard if not
+        if not isinstance(inputObject, dict):
+            return jsonify('json produced incorrect type'), 400
+        
+        # Get list of switches
+        switches = inputObject.get('switches',None)
+        # skip iterating through switches if invalid type
+        if isinstance(switches, list):
+            for switch_data in switches:
+                # skip element if invalid
+                if not isinstance(switch_data, dict):
+                    continue
+                # Get dpid and switch with that dpid
+                try:
+                    dpid = switch_data['dpid']
+                    switch = self.controller.switches[dpid]
+                # Skip if getting the dpid or the switch fails
+                except KeyError: 
+                    continue
+
+                # get metadata
+                switch_metadata = switch_data.get('metadata', None)
+                # Confirm it is of the right types
+                if isinstance(switch_metadata, dict):
+                    # Update volatile
+                    switch.extend_metadata(switch_metadata)
+                    # Update Persistent
+                    self.notify_metadata_changes(switch,'added')
+                
+                # get list of interfaces
+                interfaces = switch_data.get('interfaces', None)
+                # skip iterating through interfaces if invalid type
+                if isinstance(interfaces, list):
+                    for interface_data in interfaces:
+                        # skip element if invalid
+                        if not isinstance(interface_data, dict):
+                            continue
+                        # Get port and interface at that port
+                        try:
+                            port = interface_data['port']
+                            interface = switch.interfaces[port]
+                        # Skip if getting the port or interface fails
+                        except KeyError: 
+                            continue
+                        
+                        # get metadata
+                        interface_metadata = interface_data.get('metadata', None)
+                        # Confirm it is of the right types
+                        if isinstance(interface_metadata, dict):
+                            # Update volatile
+                            interface.extend_metadata(interface_metadata)
+                            # Update Persistent
+                            self.notify_metadata_changes(interface,'added')
+
+        # Get list of links
+        links = inputObject.get('links',None)
+        # skip iterating through switches if invalid type
+        if isinstance(links, list):
+            for link_data in links:
+                # skip element if invalid
+                if not isinstance(link_data, dict):
+                    continue
+                # Get id and link with that id
+                try:
+                    link_id = link_data['id']
+                    link = self.links[link_id]
+                # Skip if getting the id or the link fails
+                except KeyError: 
+                    continue
+
+                # get metadata
+                link_metadata = link_data.get('metadata', None)
+                # Confirm it is of the right types
+                if isinstance(link_metadata, dict):
+                    # Update volatile
+                    link.extend_metadata(link_metadata)
+                    # Update Persistent
+                    self.notify_metadata_changes(link,'added')
+        ### return confirmation that the receive file was processed correctly
+        return jsonify('Operation successful'), 201
+
     # Switch related methods
     @rest('v3/switches')
     def get_switches(self):
diff --git a/tests/integration/test_main.py b/tests/integration/test_main.py
index 1562b65..888f1e7 100644
--- a/tests/integration/test_main.py
+++ b/tests/integration/test_main.py
@@ -161,6 +161,7 @@ class TestMain(TestCase):
         """Verify all APIs registered."""
         expected_urls = [
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/interfaces'),
+         ({}, {'POST', 'OPTIONS'}, '/api/kytos/topology/v3/metadata'),
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/switches'),
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/links'),
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/'),
diff --git a/tests/unit/test_main.py b/tests/unit/test_main.py
index 54ca0bd..1b71907 100644
--- a/tests/unit/test_main.py
+++ b/tests/unit/test_main.py
@@ -1,6 +1,7 @@
 """Module to test the main napp file."""
 import time
 import json
+from io import BytesIO
 
 from unittest import TestCase
 from unittest.mock import MagicMock, create_autospec, patch
@@ -57,6 +58,7 @@ class TestMain(TestCase):
         """Verify all APIs registered."""
         expected_urls = [
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/interfaces'),
+         ({}, {'POST', 'OPTIONS'}, '/api/kytos/topology/v3/metadata'),
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/switches'),
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/restore'),
          ({}, {'GET', 'OPTIONS', 'HEAD'}, '/api/kytos/topology/v3/links'),
@@ -213,6 +215,151 @@ class TestMain(TestCase):
         self.assertEqual(response.status_code, 404, response.data)
         self.assertEqual(mock_switch.disable.call_count, 0)
 
+    @patch('napps.kytos.topology.main.Main.notify_metadata_changes')
+    def test_add_topology_metadata(self, mock_metadata_changes):
+        """Test add_topology_metadata"""
+        topology_init_state = {
+            'switches':
+            [
+                {
+                    'dpid':'00:00:00:00:00:00:00:01',
+                    'interfaces':[
+                        {'port':1,'name':'eth0'}
+                    ]
+                },
+                {
+                    'dpid':'00:00:00:00:00:00:00:02',
+                    'interfaces':[
+                        {'port':1,'name':'eth0'},
+                        {'port':2,'name':'eth1'}
+                    ]
+                },
+                {
+                    'dpid':'00:00:00:00:00:00:00:03',
+                    'interfaces':[
+                        {'port':1,'name':'eth0'}
+                    ]
+                }
+            ],
+            'links':
+            [
+                {
+                    'id': '00:00:00:00:00:00:00:01:1:00:00:00:00:00:00:00:02:2'
+                }
+            ]
+        }
+        mock_switches = {}
+        for switch_data in topology_init_state['switches']:
+            mock_switch = get_switch_mock(switch_data['dpid'])
+            mock_switch.interfaces = {}
+            for interface_data in switch_data['interfaces']:
+                mock_interface = get_interface_mock(interface_data['name'], interface_data['port'], mock_switch)
+                mock_switch.interfaces[interface_data['port']] = mock_interface
+            mock_switches[switch_data['dpid']] = mock_switch
+
+        mock_links = {}
+        for link_data in topology_init_state['links']:
+            mock_link = MagicMock(Link)
+            mock_link.id = link_data['id']
+            mock_links[link_data['id']] = mock_link
+
+        self.napp.controller.switches = mock_switches
+        self.napp.links = mock_links
+        api = get_test_client(self.napp.controller, self.napp)
+        url = f'{self.server_name_url}/v3/metadata'
+
+        topology_update = {
+            'switches':
+            [
+                {
+                    'dpid':'00:00:00:00:00:00:00:01',
+                    'metadata':{'color':'red','char':'A'},
+                    'interfaces':[
+                        {'port':1,'name':'eth0'}
+                    ]
+                },
+                {
+                    'dpid':'00:00:00:00:00:00:00:02',
+                    'metadata':{'color':'green','char':'A'},
+                    'interfaces':[
+                        {'port':1,'name':'eth0'},
+                        {'port':2,'name':'eth1','metadata':{'color':'blue'}}
+                    ]
+                },
+                {
+                    'dpid':'00:00:00:00:00:00:00:03',
+                    'metadata':{'color':'blue','char':'A'},
+                    'interfaces':[
+                        {'port':1,'name':'eth0','metadata':{'color':'pink'}}
+                    ]
+                },
+                {
+                    'dpid':'00:00:00:00:00:00:00:03',
+                    'metadata':{'color':'blue','char':'A'},
+                    'interfaces':[
+                        {'port':1,'name':'eth0','metadata':{'color':'green'}}
+                    ]
+                }
+            ],
+            'links':
+            [
+                {
+                    'id': '00:00:00:00:00:00:00:01:1:00:00:00:00:00:00:00:02:2',
+                    'metadata': {'color': 'purple'}
+                }
+            ]
+        }
+        file = BytesIO(json.dumps(topology_update).encode())
+        fileName = 'file.json'
+        response = api.post(url, data = {'file': (file, fileName)})
+        self.assertEqual(response.status_code, 201, response.data)
+        for switch_update in topology_update['switches']:
+            mock_entity = mock_switches.get(switch_update['dpid'], None)
+            if mock_entity is None:
+                continue
+            new_metadata = switch_update.get('metadata', None)
+            if new_metadata is not None:
+                mock_entity.extend_metadata.assert_any_call(new_metadata)
+                mock_metadata_changes.assert_any_call(mock_entity, 'added')
+            for interface in switch_update['interfaces']:
+                mock_entity = mock_switches.get(switch_update['dpid'], None)
+                if mock_entity is None:
+                    continue
+                new_metadata = switch_update.get('metadata', None)
+                if new_metadata is not None:
+                    mock_entity.extend_metadata.assert_any_call(new_metadata)
+                    mock_metadata_changes.assert_any_call(mock_entity, 'added')
+        for link_update in topology_update['links']:
+            mock_entity = mock_links.get(link_update['id'], None)
+            if mock_entity is None:
+                continue
+            new_metadata = link_update.get('metadata', None)
+            if new_metadata is not None:
+                mock_entity.extend_metadata.assert_any_call(new_metadata)
+                mock_metadata_changes.assert_any_call(mock_entity, 'added')
+
+        # Invalid json data type
+        file = BytesIO(json.dumps('Hello!').encode())
+        fileName = 'file.json'
+        response = api.post(url, data = {'file': (file, fileName)})
+        self.assertEqual(response.status_code, 400, response.data)
+
+        # Not a json 
+        file = BytesIO('Hello!'.encode())
+        fileName = 'file.json'
+        response = api.post(url, data = {'file': (file, fileName)})
+        self.assertEqual(response.status_code, 400, response.data)
+
+        # No Input Data
+        response = api.post(url)
+        self.assertEqual(response.status_code, 400, response.data)
+
+        # Empty field
+        file = BytesIO(''.encode())
+        fileName = ''
+        response = api.post(url, data = {'file': (file, fileName)})
+        self.assertEqual(response.status_code, 400, response.data)
+
     def test_get_switch_metadata(self):
         """Test get_switch_metadata."""
         dpid = "00:00:00:00:00:00:00:01"
diff --git a/ui/k-toolbar/main.kytos b/ui/k-toolbar/main.kytos
new file mode 100644
index 0000000..88517c2
--- /dev/null
+++ b/ui/k-toolbar/main.kytos
@@ -0,0 +1,37 @@
+<template>
+    <k-toolbar-item icon="map" tooltip="Napp Topology">
+        <k-accordion>
+            <k-accordion-item title="Update Metadata">
+                <input type="file" name="file" @change="fileChange($event.target.name, $event.target.files)">
+                </input>
+                <k-button title="Upload" :on_click="update_topology">
+                </k-button>
+            </k-accordion-item>
+        </k-accordion>
+    </k-toolbar-item>
+</template>
+<script>
+module.exports = {
+    data: function() {
+        return {
+            input : new FormData()
+        }
+    },
+    methods: {
+        update_topology(){
+            var self = this
+            $.ajax({
+                type:"POST",
+                url: this.$kytos_server_api + "kytos/topology/v3/metadata",
+                async: true,
+                data: self.input,
+                processData: false,
+                contentType: false
+            });
+        },
+        fileChange(fieldName, files){
+            this.input.set(fieldName, files[0]);
+        }
+    }
+}
+</script>
\ No newline at end of file

```

## Topology Test Environment

During system validation, I created a topology using mininet.
The following is the sourcecode for this application.

```python
from mininet.cli import CLI
from mininet.log import setLogLevel
from mininet.net import Mininet
from mininet.topo import Topo
from mininet.link import TCLink
from mininet.node import RemoteController

def run():
    topo = dTopology()
    net = Mininet( topo=topo, link=TCLink, build=False)
    c0 = RemoteController('c0', ip='127.0.0.1',port=6653)
    net.addController(c0)
    net.build()
    net.start()
    CLI( net )
    net.stop()

class dTopology (Topo):
    "Predefined topology"

    def build(self):
        s1 = self.addSwitch( 'S1')
        s2 = self.addSwitch( 'S2')
        s3 = self.addSwitch( 'S3')
        s4 = self.addSwitch( 'S4')
        s5 = self.addSwitch( 'S5')
        s6 = self.addSwitch( 'S6')
        s7 = self.addSwitch( 'S7')
        s8 = self.addSwitch( 'S8')
        s9 = self.addSwitch( 'S9')
        s10 = self.addSwitch( 'S10')
        s11 = self.addSwitch( 'S11')

        user1 = self.addSwitch( 'User12')
        user2 = self.addSwitch( 'User13')
        user3 = self.addSwitch( 'User14')
        user4 = self.addSwitch( 'User15')

        self.addLink(s1,s2)
        self.addLink(s1,user1)
        self.addLink(s2,user4)
        self.addLink(s3,s5)
        self.addLink(s3,s7) #
        self.addLink(s3,s8)#
        self.addLink(s3,s11)#
        self.addLink(s3,user3)#
        self.addLink(s3,user4)
        self.addLink(s4,s5)
        self.addLink(s4,user1)
        self.addLink(s5,s6)
        self.addLink(s5,s6)
        self.addLink(s5,s8)#
        self.addLink(s5,user1)#
        self.addLink(s6,s9)
        self.addLink(s6,s9)#
        self.addLink(s6,s10)
        self.addLink(s7,s8)#
        self.addLink(s8,s9)
        self.addLink(s8,s9)
        self.addLink(s8,s10)
        self.addLink(s8,s11)
        self.addLink(s8,user3)#
        self.addLink(s10,user2)
        self.addLink(s11,user2)
        self.addLink(user1,user4)

if __name__ == '__main__':
    setLogLevel( 'info' )
    run()

```

Additionally, I specified the metadata for this topology with the following
document.

```json
{
    "switches":[
        {
            "dpid":"00:00:00:00:00:00:00:01",
            "metadata":{
                "lat":0,
                "lng":0
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:02",
            "metadata":{
                "lat":3,
                "lng":0
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:03",
            "metadata":{
                "lat":3,
                "lng":2
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:04",
            "metadata":{
                "lat":-0.5,
                "lng":1.5
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:05",
            "metadata":{
                "lat":0,
                "lng":2
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:06",
            "metadata":{
                "lat":0,
                "lng":3
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:07",
            "metadata":{
                "lat":2.5,
                "lng":2.5
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:08",
            "metadata":{
                "lat":3,
                "lng":3
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:09",
            "metadata":{
                "lat":3,
                "lng":2
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:0a",
            "metadata":{
                "lat":3,
                "lng":5
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:0b",
            "metadata":{
                "lat":4.5,
                "lng":2
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:0c",
            "metadata":{
                "lat":0,
                "lng":1
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:0d",
            "metadata":{
                "lat":5,
                "lng":3
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:0e",
            "metadata":{
                "lat":3.5,
                "lng":2.5
            }
        },
        {
            "dpid":"00:00:00:00:00:00:00:0f",
            "metadata":{
                "lat":3,
                "lng":1
            }
        }
    ],
    "links": [
        {
            "id":"00:00:00:00:00:00:00:01:1:00:00:00:00:00:00:00:02:1",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":105
            }
        },
        {
            "id":"00:00:00:00:00:00:00:01:2:00:00:00:00:00:00:00:0c:1",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":1
            }
        },
        {
            "id":"00:00:00:00:00:00:00:02:2:00:00:00:00:00:00:00:0f:1",
            "metadata":{
                "reliability": 5,
                "bandwidth": 100,
                "delay": 10
            }
        },
        {
            "id":"00:00:00:00:00:00:00:03:1:00:00:00:00:00:00:00:05:1",
            "metadata":{
                "reliability": 5,
                "bandwidth": 10,
                "delay": 112
            }
        },
        {
            "id":"00:00:00:00:00:00:00:03:2:00:00:00:00:00:00:00:07:1",
            "metadata":{
                "reliability": 5,
                "bandwidth": 100,
                "delay": 1
            }
        },
        {
            "id":"00:00:00:00:00:00:00:03:3:00:00:00:00:00:00:00:08:1",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":1
            }
        },
        {
            "id":"00:00:00:00:00:00:00:03:4:00:00:00:00:00:00:00:0b:1",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":6
            }
        },
        {
            "id":"00:00:00:00:00:00:00:03:5:00:00:00:00:00:00:00:0e:1",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":1
            }
        },
        {
            "id":"00:00:00:00:00:00:00:03:6:00:00:00:00:00:00:00:0f:2",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":10
            }
        },
        {
            "id":"00:00:00:00:00:00:00:04:1:00:00:00:00:00:00:00:05:2",
            "metadata":{
                "reliability":1,
                "bandwidth":100,
                "delay":30,
                "ownership": "A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:04:2:00:00:00:00:00:00:00:0c:2",
            "metadata":{
                "reliability":3,
                "bandwidth":100,
                "delay":110,
                "ownership": "A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:05:3:00:00:00:00:00:00:00:06:1",
            "metadata":{
                "reliability":1,
                "bandwidth":100,
                "delay":40
            }
        },
        {
            "id":"00:00:00:00:00:00:00:05:4:00:00:00:00:00:00:00:06:2",
            "metadata":{
                "reliability":3,
                "bandwidth":100,
                "delay":40,
                "ownership": "A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:05:5:00:00:00:00:00:00:00:08:2",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":112
            }
        },
        {
            "id":"00:00:00:00:00:00:00:05:6:00:00:00:00:00:00:00:0c:3",
            "metadata":{
                "reliability": 3,
                "bandwidth":100,
                "delay":110,
                "ownership": "A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:06:3:00:00:00:00:00:00:00:09:1",
            "metadata":{
                "reliability":3,
                "bandwidth":100,
                "delay":60
            }
        },
        {
            "id":"00:00:00:00:00:00:00:06:4:00:00:00:00:00:00:00:09:2",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":62
            }
        },
        {
            "id":"00:00:00:00:00:00:00:06:5:00:00:00:00:00:00:00:0a:1",
            "metadata":{
                "bandwidth":100,
                "delay":108,
                "ownership": "A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:07:2:00:00:00:00:00:00:00:08:3",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":1
            }
        },
        {
            "id":"00:00:00:00:00:00:00:08:4:00:00:00:00:00:00:00:09:3",
            "metadata":{"reliability": 3,"bandwidth": 100, "delay":32}
        },
        {
            "id":"00:00:00:00:00:00:00:08:5:00:00:00:00:00:00:00:09:4",
            "metadata":{"reliability": 3,"bandwidth": 100, "delay":110}
        },
        {
            "id":"00:00:00:00:00:00:00:08:6:00:00:00:00:00:00:00:0a:2",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "ownership":"A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:08:7:00:00:00:00:00:00:00:0b:2",
            "metadata":{
                "reliability":3,
                "bandwidth":100,
                "delay":7
            }
        },
        {
            "id":"00:00:00:00:00:00:00:08:8:00:00:00:00:00:00:00:0e:2",
            "metadata":{
                "reliability":5,
                "bandwidth":100,
                "delay":1
            }
        },
        {
            "id":"00:00:00:00:00:00:00:0a:3:00:00:00:00:00:00:00:0d:1",
            "metadata":{
                "reliability":3,
                "bandwidth":100,
                "delay":10,
                "ownership":"A"
            }
        },
        {
            "id":"00:00:00:00:00:00:00:0b:3:00:00:00:00:00:00:00:0d:2",
            "metadata":{
                "reliability":3,
                "bandwidth":100,
                "delay":6
            }
        },
        {
            "id":"00:00:00:00:00:00:00:0c:4:00:00:00:00:00:00:00:0f:3",
            "metadata":{
                "reliability":5,
                "bandwidth":10,
                "delay":105
            }
        }
    ]
}
```
OpenTox Dataset
===============

* An OpenTox REST Webservice
* Stores associations between compounds and features in datasets
* Implements a subset of the [OpenTox compound API 1.2](http://opentox.org/dev/apis/api-1.2/dataset)
* Supports the internal YAML representation of opentox-ruby

REST operations
---------------

    Get a list of datasets  GET     /       -                       List of dataset URIs    200,400,404
    Get a dataset           GET     /{id}   -                       Dataset representation  200,400,404
    Upload a dataset        POST    /       Dataset representation  Dataset URI             200,400,404 
    Delete a dataset        DELETE  /{id}   -                       -                       200,404
    Delete all datasets     DELETE  /       -                       -                       200,404

Supported MIME formats (http://chemical-mime.sourceforge.net/)
--------------------------------------------------------------

* application/rdf+xml (default): read/write OWL-DL
* application/x-yaml: read/write YAML

Examples
--------

Get a list of all datasets

    curl http://webservices.in-silico.ch/dataset

Upload a dataset

    curl -X POST -H "Content-Type:application/rdf+xml" --data-binary @{my_rdf_file} http://webservices.in-silico.ch/dataset

Get a dataset representation

    curl http://webservices.in-silico.ch/dataset/{id}

Delete a dataset

    curl -X DELETE http://webservices.in-silico.ch/dataset/{id}

[API documentation](http://rdoc.info/github/opentox/dataset)
------------------------------------------------------------

Copyright (c) 2009-2011 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.


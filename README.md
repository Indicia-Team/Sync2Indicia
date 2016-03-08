# Sync2Indicia
A desktop tool for automating the upload of CSV files into an Indicia warehouse.

## Building Sync2Indicia

The tool currently requires Delphi 7 to build. To build the tool:

* Clone the repository.
* Download the JSON Delphi library source from https://sourceforge.net/projects/lkjson/files/lkJSON/ and place the uLkJSON.pas file into the delphi-7 folder.
* In the delphi-7 folder is a project you can load into Delphi 7 and compile.

## Using Sync2Indicia

The Sync2Indicia tool allows you to create synchronisation links between a local database and an Indicia warehouse. At the moment this only supports upload of information to the warehouse, though it is possible to upload any type of data supported by the Indicia web services from any local database supporting an OLEDB connection string. The task of setting up synchronisation links requires some experience of writing SQL queries against your local database as well as an understanding of the warehouse data, as the synchronisation link file format is designed for complete flexibility rather than simplicity. Currently the tool is supplied only as a Windows executable.

### Setting up the tool

The tool can be downloaded from the [Indicia downloads page](http://code.google.com/p/indicia/downloads/list). This is a Windows executable which you should unzip to a suitable folder. The configuration for the tool is provided by creating a folder in your My Documents or Public  Documents folder called Sync2Indicia (e.g. C:\Users\_Username_\Documents or C:\Users\Public\Documents\Sync2Indicia are both valid Windows 7 paths). Note that using My Documents rather than Public Documents is inherently more secure.

### Files you must create
**Warehouse.txt**

This file declares a connection to the warehouse you want to upload data to. It should contain 3 lines which define the *warehouse_url*, *website_id* and *website_password* values for the connection. The following shows a connection to the demonstration website on a local installation of the warehouse:

```
warehouse_url=http://localhost/indicia/index.php
website_id=1
website_password=password
```

**LocalConnectionString.txt**

This file declares an OLEDB connection string which provides a connection to the local database the data is being uploaded from. It contains the connection string to be used and nothing more. If the file is omitted, then the Sync2Indicia tool will check to see if there is an installation of Recorder 6 on the local machine and will use that if available. Here’s an example which declares a connection to a database called MyRecords on a SQL Server called MYSERVER/SQLSERVER, using the current Windows logon to authenticate onto the database:
```
Provider=SQLOLEDB.1;Integrated Security=SSPI;Persist Security Info=False;Initial Catalog= MyRecords;Data Source= MYSERVER/SQLSERVER
```

**link files**

For each type of data you want to synchronise, create a file with a suitable name and the file extension .link. Inside this file you need to provide the settings which let the Sync2Indicia tool upload the data. Here is a template for the file:

```
# A template to upload data into Indicia
direction=upload
model=(warehouse model name)
=fixedvalues=
(list of fixed values that are applied to every row)
 =mappings=
(mappings from the local database fieldname to the warehouse fieldname)
=query=
(SQL statement to run on the local database)
=existingrecordmatchfields=
indiciaKeyField=(Indicia fieldname)
localKeyField=(local fieldname)
=existingrecordcopyfields=
(Fields to be copied over when existing records are found)
```

Note that any line starting with # represents a comment. Fill in the template as follows (a complete example is given below for your reference):

 - model:  Set this to the name of the model you are uploading data into on the warehouse. This is normally the singular version of the table name. For example to upload occurrences or taxa in a species list use *occurrence* and *taxa_taxon_list* respectively. 
 - fixedvalues: When uploading data, you may wish to set default values that apply to all rows rather than having to specify them individually for each row. For example when uploading taxa into a checklist you might like to set the language to latin for all rows. Specify each fixed value on a separate line beneath the `=fixedvalues=` heading, with the Indicia warehouse field name (in format _modelname_:_fieldname_) followed by an equals sign then the value to set. 
 - mappings: In this section declare mappings from the output fields of your local database query to the warehouse field names you want to map the data into (in format _modelname_:_fieldname_). Specify each mapping on a separate line with the local database fieldname followed by an equals sign then the Indicia warehouse fieldname.
 - query: Specify an SQL query that will be run against the local database to pick up all the data to synchronise. Use a replacement tag *#lastrun#* in your query to specify a filter so that the query only picks up records updated or added since the last synchronisation run, to minimise the work that has to be done. _The SQL statement must output the same fields as defined in the mappings section, in the same order_. If you specify a field called *new* in the output of this query at the end of the list of fields, which returns 1 for any new records as opposed to modified records, then the Sync2Indicia tool can more efficiently work out exactly what updates to apply.
 - existingrecordmatchfields: This section allows you to define how the Sync2Indicia tool  will detect records that already exist on the warehouse so that it can update these records rather than create new ones all the time. To do this you need a value which is stored on both the warehouse and the local database that uniquely identifies the record and can therefore be used to match between the warehouse and local records. Typically when uploading data from an external datasource you will upload the primary key or other unique identifier into the warehouse model’s external_key field and use that field to match. Specify fieldnames for indiciaKeyField and localKeyField on 2 separate lines. The indiciaKeyField setting must name a field that is available in the *detail* view for the warehouse model when access via the data services. The field should be a unique identifier for each record on the warehouse. The equivalent field in the local database query must be set by localKeyField.
 - existingrecordcopyfields - When an existing record is found, the available information identifying that record is the output of the *detail view* from the warehouse data services. Any key fields in this output must be mapped back to the warehouse model fields that need to contain these values. This includes the primary key of the record and also any foreign keys to detail records that are essential parts of the information stored on the warehouse. An example of the latter is when a taxa_taxon_list record is updated you must also specify the existing taxon_id and taxon_meaning_id values to avoid new taxa or taxon_meanings records being created. Specify each id field on a new line, in the format _fieldname from detail view_:_warehouse field name_.

### Scheduling
Since Sync2Indicia is a simple executable with no user response required, you can simply automate it using the standard **Task Scheduler** tool provided with Windows.

### Examples
The following example file specifies a synchronisation link for a taxon list in Recorder 6 where taxon_list_key is TESTDATA01234567. The data is synched into the taxon list with ID 26 on the warehouse and makes all the records have their language id set to 2 (latin) and taxon group id 63 (Mammals for this particular warehouse). 

Please note that although it is possible to upload lists from the standard Recorder 6 Taxon Dictionary using this method, you should arrange for permission to use the lists in this way from the author of the list before doing so.
```
# A synchronisation link file to upload taxa from the Recorder Taxon Dictionary to Indicia. 
direction=upload
model=taxa_taxon_list
=fixedvalues=
taxa_taxon_list:taxon_list_id=26
taxon:language_id=2
taxon:taxon_group_id=63
=mappings=
taxon_version_key=taxon:external_key
taxon=taxon:taxon
=query=
select tv.taxon_version_key, t.item_name as taxon, 
  case when tli.entry_date>='#lastrun#' or tlv.entry_date>='#lastrun#' or t.entry_date>='#lastrun#' then 1 else 0 end as new
from taxon_list_version tlv 
inner join taxon_list_item tli on tli.taxon_list_version_key=tlv.taxon_list_version_key 
inner join taxon_version tv on tv.taxon_version_key=tli.taxon_version_key 
inner join taxon t on t.taxon_key=tv.taxon_key 
where tlv.taxon_list_key=' TESTDATA01234567'
and (tli.entry_date>='#lastrun#' or tli.changed_date>='#lastrun#'
or tlv.entry_date>='#lastrun#' or tlv.changed_date>='#lastrun#'
or t.entry_date>='#lastrun#' or t.changed_date>='#lastrun#')
=existingrecordmatchfields=
indiciaKeyField=external_key
localKeyField=taxon_version_key
=existingrecordcopyfields=
id=taxa_taxon_list:id
taxon_id=taxon:id
taxon_meaning_id=taxa_taxon_list:taxon_meaning_id
```

Finally, this more complex example illustrates an upload link for taxon occurrences in Recorder 6 into an Indicia warehouse. It does not synch any custom attributes. The data is synchronised into an existing warehouse survey with ID = 1 from the Recorder 6 survey with survey_key=TESTDATA00000001. Only verified data is uploaded.

```
# Upload occurrence records from Recorder into Indicia.
direction=upload
model=occurrence
=fixedvalues=
sample:survey_id=1
# All records are verified
occurrence:record_status=V
=mappings=
taxon_occurrence_key=occurrence:external_key
date_start=sample:date_start
date_end=sample:date_end
vague_date_type=sample:date_type
spatial_ref=sample:entered_sref
spatial_ref_system=sample:entered_sref_system
location_name=sample:location_name
# Use the fk_ notation to lookup taxa on the warehouse.
taxon=occurrence:fk_taxa_taxon_list
sample_comment=sample:comment
occurrence_comment=occurrence:comment
=query=
select o.taxon_occurrence_key, 
  CASE WHEN s.vague_date_start IS NULL OR s.vague_date_start = 0 THEN NULL ELSE dateadd(day, s.vague_date_start, '1899-12-30') END as date_start, 
  CASE WHEN s.vague_date_end IS NULL OR s.vague_date_end = 0 THEN NULL ELSE dateadd(day, s.vague_date_end, '1899-12-30') END as date_end, 
  s.vague_date_type, s.spatial_ref, 
  CASE s.spatial_ref_system 
    WHEN 'LTLN' THEN '4326'
    ELSE s.spatial_ref_system
  END AS spatial_ref_system,
  CASE 
    WHEN ln.item_name + s.location_name IS NULL THEN
# at least one of the location name values is null, so don't bother joining
      ISNULL(ln.item_name,'') + ISNULL(s.location_name,'')
    ELSE
# both are present, so include a separator
      ISNULL(ln.item_name + '-','') + ISNULL(s.location_name,'')
  END AS location_name,
  itn.actual_name as taxon, dbo.ufn_RtfToPlaintext(s.comment) as sample_comment, dbo.ufn_RtfToPlaintext(o.comment) as occurrence_comment
from taxon_occurrence o
inner join taxon_determination td on td.taxon_occurrence_key=o.taxon_occurrence_key and td.preferred=1
inner join index_taxon_name itn on itn.taxon_list_item_key=td.taxon_list_item_key
inner join sample s on s.sample_key=o.sample_key
left join location_name ln on ln.location_key=s.location_key and ln.preferred=1
inner join survey_event se on se.survey_event_key=s.survey_event_key and se.survey_key='TESTDATA00000001'
# Only upload verified data
where o.verified=2
and (o.entry_date>='#lastrun#' or o.changed_date>='#lastrun#' or
  s.entry_date>='#lastrun#' or s.changed_date>='#lastrun#')
=existingrecordmatchfields=
indiciaKeyField=external_key
localKeyField=taxon_occurrence_key
=existingrecordcopyfields=
id=occurrence:id
```
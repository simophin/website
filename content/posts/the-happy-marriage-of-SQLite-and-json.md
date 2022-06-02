---
title: "The happy marriage of SQLite and JSON"
date: 2022-06-01T21:43:40+12:00
---

I've been writing yet another CRUD app, shameless promotion here: [simple-logbook](https://github.com/simophin/simple-logbook). 
Its sole purpose was to learn Rust, React and record my own finances! It's such a fun project: I made some very satisfying database
design that I just want to share here with you.

## The curse of object oriented models in the database

Think about the accounting software I've written: you have a bunch of financial transactions, for each transaction, you
will have some properties like `amount`, `date`, etc. There are also other affiliated objects as well, like
attachments, which resembles a one to many relationships: one transaction can have multiple attachments.

If you are to model the transaction and attachment, you'd have things like this:

```sql
-- Transaction table
CREATE TABLE transactions(
    id TEXT PRIMARY KEY,
    created DATETIME,
    amount INTEGER,
);

-- Attachment table
CREATE TABLE transaction_attachments(
    id TEXT PRIMARY KEY,
    transactionId TEXT REFERENCES transactions(id) ON DELETE CASCADE,
    filePath TEXT,
    fileSize INTEGER,
    created DATETIME,
);
```

So now we have two tables linked together by the foreign keys. It's pretty standard way of modelling the
hierarchy and it's neat.

However, when it comes to mapping it back to a programming language, says Kotlin, we might have these magical models:

```kotlin
@Entity
data class Transaction(
    @Id val id: String,
    val created: DateTime,
    val amount: Int,
    @OneToMany(targetEntity = Attachment:class)
    val attachments: List<Attachment>,
)

@Entity
data class Attachment(
    @Id val id: String,
    val filePath: String,
    val fileSize: Int,
    val created: DateTime,
)
```

This mapping is a very natural way of how we think about these two models: you have a List of `Attachment` who belong
to a single `Transaction`. Just perfect!

However, once we come to the implementation land, we will quickly discover the shortfall of row based Record SQL uses.
To be able to get a single transaction, you will likely run similar code like this:

```kotlin
fun getTransaction(val id: String) {
    entityManager.beginTransaction();
    val transactionRow = entityManager.querySingle("SELECT * FROM transactions WHERE id = {}", id);
    val transaction = mapRow(transactionRow)
    val attachmentRows = entityManager.queryList("SELECT * FROM attachments WHERE transactionId = {}", transaction.id);
    entityManager.endTransaction();

    transaction.attachments = mapRows(attachmentRows)

    return transaction
}
```

So you end up with running two queries, what's worse, you rely on the programming language to bridge the foreign key data
between two queries. Not nice! I'd feel very messy having to do this. Although you don't have to do it by hand, the underlying
framework like Hibernate probably does that for you! Sweeping the dust into the corner is not my style, there must be 
a better way of doing this!

When you come to think about this, the first thing you want to ask is why can't we squeeze this into one SQL query. SQL is
a powerful language, surely there's a way to do it!

It turns out, because the result you are getting from the query is linear row based, but the data you query is tree like structure,
there's no way to fit it neatly into a linear layout. A naive way of doing this is just to flatten all the things into rows. Like
this:

```sql
SELECT transactions.*, attachments.* FROM transactions
LEFT JOIN attachments ON attachments.transactionId = transactions.id
WHERE transactions.id = ?
```

So you are joining the tables together and you will have (says you have two attachments):

| id | transactionId | created              | amount | filePath              | fileSize |
|----|---------------|----------------------|--------|-----------------------|----------|
| 1  | tx1           | 2020-10-10T12:00:00Z | 123    | /data/attachment1.jpg | 156      |
| 2  | tx1           | 2020-10-11T13:00:00Z | 123    | /data/attachment2.jpg | 521      |

Now all the things are smashed together, the transaction's data will be repeated as many rows as `Attachment`. That is the way
it works: by flatten an hierarchy into rows, you will have as many rows as the most numerous models, and all other info
will be repeated along the way.

In the programming language, you'll have to take care of this repetition by only extracting transaction data at most once, while
extract the attachment data line by line. Essentially you are pushing more work into the programming language.

Another problem of this approach is the pollution of property names. Because all properties from all models are smashed together,
the ones with same name will get overridden and you'll never be sure which one has the true values. So you have to carefully rename
them in the SQLs and the mapping in Java will get complicated very fast.

## JSON to the rescue

Here comes a problem we are asking: is there a way to query hierarchy data in one query?

With the help of JSON, the answer is yes. Here is how, in SQLite:

```sql
SELECT transactions.*,
    (
        SELECT json_group_array(json_object(
            'id', a.id,
            'filePath', a.filePath,
            'fileSize', a.fileSize,
            'created', a.created
        )) 
        FROM transaction_attachments AS a 
        WHERE transactionId = transactions.id
    ) AS attachments
FROM transactions
```

You'll get: 

| id | created              | amount | attachments                                                                           |
|----|----------------------|--------|---------------------------------------------------------------------------------------|
| 1  | 2020-10-10T12:00:00Z | 123    | [{"id":"1", "filePath":"/data/attachment1.jpg", "fileSize": 123, "created": ""}, ...] |

Attachments have been flatten into a JSON string! How cool is that. So we'll make changes to the model accordingly, we can now have a
custom entity serializer instead!

```kotlin
@Entity
data class Transaction(
    @Id val id: String,
    val created: DateTime,
    val amount: Int,
    
    @Converter(converter = AttachmentListJsonConverter::class)
    val attachments: List<Attachment>,
)

// This concrete class ensures the parameter type doesn't get erased
class AttachmentListJsonConverter : JsonConverter<List<Attachment>>()

abstract class JsonConverter<T> : AttributeConverter<T, String> {
    private val t: Type = deductTypeUsingReflection(this);
    ...
}
```

I'd love to have a more generic implementation of a `JsonConverter` but due to its API limit you'll have to provide
a concrete implementation of `AttributeConverter` to put it on the property. But this way we can tell JPA we will deserialize/serialize
the `attachments` as JSON!

So now we can query a piece of hierarchy data in just one SQL! How cool is that.


## Can we push it further?

We have successfully "squeeze" multiple queries into one. But can we do better? 

If we look at the Kotlin model `Transaction` carefully, surely it will be good to have a "table" in the database that matches exactly to 
its field? Right now in the database, we don't have `attachments`, it needs a separate query into the attachments table. It will 
be super nice to have a table like this:

```sql
CREATE TABLE transactions(
    ...
    attachments ARRAY<Attachment> 
);
```

Sadly there's no such generic type in common SQL database, definitely not SQLite! 

Good news is we can at least get there in half way!

Have you heard about a view? A database view is just a glorified query that looks like a table. Instead of creating a table with type we can't have,
we can create a view instead:

```sql
CREATE VIEW transaction_details AS SELECT transactions.*,
    (
        SELECT json_group_array(json_object(
            'id', a.id,
            'filePath', a.filePath,
            'fileSize', a.fileSize,
            'created', a.created
        )) 
        FROM transaction_attachments AS a 
        WHERE transactionId = transactions.id
    ) AS attachments
FROM transactions
```

This view is equivalent to this table:

| Column      | Type     | Note                     |
|-------------|----------|--------------------------|
| id          | TEXT     | Key                      |
| created     | DATETIME |                          |
| amount      | INTEGER  |                          |
| attachments | TEXT     | Json array of Attachment |


So now you can query this view just like you would with a table!

```sql
SELECT * FROM transaction_details
```

And with that and our updated Kotlin model you just return all the information at once, with a much clearer SQL! Of course you can do filtering 
on the table like you would.

## Can we...push even further?

We have talked about how we improve the query by using JSON & Views. One topic we haven't touched is updating and deleting. If we stick to our
models before, in order to update the attachments a transaction has, you will need to operate on the `transaction_attachments` table. Wouldn't it
be nice if we don't need to touch the `transaction_attachment` table at all? Translating to Kotlin land, we just update the `attachments` property of the
`Transaction` and all will be written nicely into the `transaction_attachment` table.

At the first thought, you would just want to write into the `transaction_details` VIEW we just created. Sadly, a view is read-only.

Or, is it?

Turns out you can "write" to a view in SQLite. This is how you do it: instead of writing into a view, you redirect the INSERT/UPDATE/DELETE to the real table
using SQL Trigger! This is some truly fancy thing we can do, let's see it:

```sql

-- Create a trigger that replaces "INSERT INTO the view" to "INSERT INTO the real table"
CREATE TRIGGER transaction_details_insert
INSTEAD OF INSERT ON transaction_details
BEGIN
    -- Create the transaction first
    INSERT INTO transactions (id, amount, created)
    VALUES (NEW.id, NEW.amount, NEW.created);

    -- Create the attachments from the JSON string
    INSERT INTO transaction_attachments (transactionId, id, filePath, fileSize, created)
    SELECT NEW.id,
           json_extract(value, '$.id'),
           json_extract(value, '$.filePath'),
           json_extract(value, '$.fileSize'),
           json_extract(value, '$.created')
    FROM json_each(NEW.attachments)
END
```

So now you have it, we are deep into some advance SQLite features here but you get the idea: we can put a little program (triggers) in the database to replace
the operations on views. I'll leave the deletion part to you to figure out.

## Conclusions
Once you have all this in place, you can have a "table" that a programming language can map exactly to, all CRUD included, and with the correct hierarchy in the 
db! Just with a little help of JSON extension in SQLite, it's truly a happy marriage!
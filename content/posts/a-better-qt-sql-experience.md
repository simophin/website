---
title: "A Better Qt + SQL Experience"
date: 2021-04-10T16:47:16+12:00
---

When I was developing a match maker app for the local badminton club, I 
missed Java so much. Not that I miss the heavy JVM hoarding all your memory, 
but all the convenience Java brings when it comes to database access. The
 most crucial part of that convenience, in my opionion, is no need to bind 
 variables to a result row manually.

Imagine this query: 

```sql
SELECT id, name, age FROM users;
```

In Java you can pretty much do this;

```java
public class User {
    @Column("id")
    String id;

    @Column("name")
    String name;

    @Column("age")
    int age;
}

List<Users> users = query(sql);
```

But in Qt, you will have to wire up all the binding yourself:

```cpp
QSQLQuery query("SELECT * FROM Users");
while (query.next()) {
    QString id = query.value(0).toString();
    QString name = query.value(1).toString();
    int age = query.value(2).toInt();
}

```

It's really dumb that you have to repeat yourself like that
for every query you make. And you have to be extra careful about the column order here as well. Wouldn't it be nice to have the compiler does the binding for you? 

So I come up with this

```cpp
#include <QObject>

struct User {
    Q_GADGET

    DECLARE_PROPERTY(QString, id);
    DECLARE_PROPERTY(QString, name);
    DECLARE_PROPERTY(int, age);
};

auto rs = get_result_set();
auto user = map_result_set<User>(rs);
```

How do I do this? 

Well the answer lies in Qt's property system. 
Apparently Qt uses `moc` to add some basic reflection support
to C++. In the example above, I have added a `Q_GADGET` macro,
this tells `moc` this structure is a 'gadget' - a lightweight
version of `QObject`. In Qt, `QObject` supports properties and
meta functions - they can be queried and run in the runtime. It
also adds in some meta data about the class. Anyway, the most 
important thing that enables us to automatically map database
rows into data structure, is the ability to read and update 
the property dynamically. Consider this:

```cpp
User user;
const QMetaObject &meta = User::staticMetaObject;
// Get property at index 0
QMetaProperty prop0 = meta.property(0);

// Write user's age
if (prop.name() == QStringLiteral("age")) {
    prop0.writeOnGadget(reinterpret_cast<void *>(&user), 30);
}

```

Using this piece of code you can then iterate through dataset and set the value of given column to the gadget's property.
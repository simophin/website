---
title: "Why I Like Room"
date: 2021-04-10T17:01:16+12:00
draft: true
---

This article talks about the [Room Persistent Framework](https://developer.android.com/training/data-storage/room),
part of Android's de-facto standard library: Jetpack.

Working with Java for so many years, one of the things I really want to see is a nice to use ORM framework.
The last thing I want to do is debugging some weird data issues with live Hibernate objects. I had been an 
early adopter of Android's Room library, I must admit this is the one thing that satisfies me on every
aspect.

So what are my problems with ORM frameworks?

### Live object is a sin

Consider this very common Hibernate practice:

```java
@Entity
public class Zoo {
    @OneToMany(mappedBy = "animal")
    private List<Animal> animals;
    // getter and setter, etc.
}

@Entity
public class Animal {
    @ManyToOne
    @JoinColumn(name = "zoo_id", referencedColumnName = "id")
    private Zoo zoo;
    // getter and setter, etc.
}
```

Now if you load a `Zoo`, by default, you will have lazily-loaded `animals`. Only when you access the
`animals` will the query actually be made. This is to improve the query performance. However, this comes with a price:

1. Black magic applied on the getter: `getAnimals`. You can imagine some byte code manipulation, or some reflection
   magic has to be used to override the getter at runtime. It's ok for everyday use but if you want to debug deeper
   into the code, the black magic becomes a cluster nightmare to step through.
   
2. `Zoo` is no longer a POJO, it becomes live. A POJO is supposed to be just a simple representative of a piece of data. 
   By overriding the getter with the lazy loading logic, it violates the idea of separation of concerns: you bring 
   business logic into the domain object. The outcome is awful:
   
   * If you had run the `Zoo` query in a transaction, and you call the `getAnimals` after the transaction completes,
     you will get a nasty exception because Hibernate has no way to guarantee the transaction after it finishes. You
     need to be very careful where and when you can call `getAnimals`. You can't pass the objects into other threads
     either. In fact, you probably can't do much with the live objects.
     
   * Even you don't need the query to be atomic, if you use these live objects in other threads, you can accidentally 
     block an important thread by running SQL query on it.
     
     
The similar things happen to the famous alternative database `Realm`: the live objects are the core part of it, so much 
that the implementation details have to leak all over the codebase, I guess it's good for its business, once you 
start using Realm, it's really hard to get rid of it. This is what I mean:

Considering you have a data access layer, you would have

```java
interface DataAccess {
    List<Animal> getAnimals();
    // Or fancier...
    Observable<List<Animal>> streamAnimals();
}
```

Now you are free to implement it in whatever database you are using.

For Realm's best practice, you can't have that kind of generic interface anymore. (You still can, I'll explain later) 

Instead, you will have to do this

```java
interface DataAccess {
    RealmResult<Animal> getAnimals();
}
```

Why? Realm's records are all live objects. It's backed by native code and magically the data inside `RealmResult` can
change at anytime! That's why once you get the `RealmResult`, you have to use it within the thread you make the query, 
otherwise the realtime data change will screw you up big time due to race condition. Although `RealmResult` 
implements `List`, it has so much limitation to it so that if you hide the implementation under the first form of interface, 
the interface users are bound to misuse it by passing it around! So it's far better to use `RealmResult` directly. 
This of course, will cause implementation details - the Realm library - to leak all over your codebase. 

Of course, as stated before, you can still implement the `List` version of interface safely, by coping the data from
the live Realm objects into a POJO version. Ha! This is exactly what we are talking about, live object is just so 
against common software pattern that I don't think it's worth the cost!

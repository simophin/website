---
title: "Kotlin coroutine and cancellation"
date: 2021-10-18T22:28:16+13:00
---

I've been using a lot of async frameworks: Javascript async/await, Kotlin coroutine, 
Goroutine, Rust async, etc. I have to say the crown of handling cancellation must be 
given to Kotlin. Let's start with why you need to care about cancellation.

### Stop touching my views!
Let's see an example of the poorest of the poor: Javascript. It provides next to 
nothing for you to cancel an operation. Consider this,

```typescript
function sleep(mills) {
  return new Promise((resolve) => {
    setTimout(resolve, mills);
  });
}

async function submitForm(formValues) {
   await api.postForm(formValues);
   showPrompt("submit successfully");
   await sleep(3000);
   redirectToHomePage();
}
```

Imagine the user clicks the submit button but the API is taking its time so he just clicks on something else, maybe
start drafting up a blog... 60s later the api's result has come back and bang! You are taken to the home page
you just lost your work!

So you might want to cancel the submission, but how?

Granted the ajax api provides a `CancellationToken` you can use, so you might have this instead:

```typescript
async function submitForm(formValues, cancelToken) {
   await api.postForm(formValues, {cancelToken});
   showPrompt("submit successfully");
   await sleep(3000);
   redirectToHomePage();
}
```

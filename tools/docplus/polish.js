#!/usr/bin/env node

// 这个程序是一个 nim 文档的修复器。我对 nim doc 输出的 HTML 十分不满意，这个修复器会按照我所期望
// 的 HTML 文档格式进行一些调整。
//
// 注意：这个程序依赖 NodeJS 以及一些软件库，主要有 JSDOM
// We repair it!

const Fs = require('fs')
const Path = require('path')
const JsDom = require('jsdom')

const DOCK_HACK_JS = Path.resolve(__dirname, 'dochack.js')

class DocPolisher {
  constructor(document) {
    this.document = document
  }

  polishCSS() {
    this.document.head.insertAdjacentHTML("beforeend", `<style>
    h1 {
      border-bottom: none;
    }
    
    .container h1.title {
      width: 80.0%;
    }
    .container > .row > .columns:first-of-type {
      float: none;
      position: fixed;
      right: 0;
      top: 0;
      width: 18%;
      height: 100%;
      padding-top: 40px;
    }
    .footer {
      width: 80.0%;
    }
    #toc-list {
      height: calc(100% - 169px);
      overflow-y: hidden;
    }
    #toc-list:hover {
      overflow-y: auto;
    }
    #content.columns {
      margin-left: auto;
      margin-left: 1%;
      margin-right: 1%;
    }
  
    pre {
      width: 100%;
      overflow: hidden;
      padding: 0.5em 1em;
    }
    pre:hover {
      overflow: auto;
    }
  
    .pre {
      font-family: Fira Code,Anonymous Pro,Monaco,Menlo,Consolas,Droid Sans Mono,Monospace;
      display: inline-block;
      padding: 0px 0.3em;
      color: #2a6e6b; /*#2a6e6b #4a7e7b*/
      font-weight: bold;
      border-radius: 2px;
      background-color: transparent;
    }

    .r-fragment {
      padding: 0 0 0 30px;
      border-left: 1px solid rgb(216,216,216);
      margin: 40px 0;
    }

    .r-ol {
      padding-left: 1em;
    }

    p {
      margin-top: 20px;
      margin-bottom: 20px;
    }
  </style>`)
  }

  polishJS() {
    const scripts = this.document.querySelectorAll("script")
    for (let i = 0, len = scripts.length; i < len; i++) {
      if (scripts[i].src === "dochack.js") {
        scripts[i].src = "/dochack.js"
      }
    }
  }
  
  removeChildTexts(elem) {
    var childNodes = elem.childNodes
    var texts = []
    for (let j = 0, len = childNodes.length; j < len; j++) {
      if (childNodes[j].nodeType == 3 /*Text*/) {
        texts.push(childNodes[j])
      }
    }
    for (let text of texts) {
      elem.removeChild(text)
    }
  }
  
  polishEnums() {
    const keywordElems = this.document.querySelectorAll("pre > .Keyword")
    for (let i = 0, len = keywordElems.length; i < len; i++) {
      const elem = keywordElems[i]
      if (elem.innerHTML === 'enum') {
        this.removeChildTexts(elem.parentElement)
  
        const children = elem.parentElement.children
        for (let i = 0, len = children.length; i < len; i++) {
          if (children[i].classList.contains('Other')) {
            if (children[i].innerHTML == '=') {
              children[i].innerHTML = ' ' + children[i].innerHTML + ' '
            }
            if (children[i].innerHTML == ',') {
              let j = i + 1
              if (j < len) {
                if (children[j].classList.contains('Comment')) {
                  children[j].innerHTML = '  ' + children[j].innerHTML + '\n  '
                }
              }
              children[i].innerHTML = children[i].innerHTML + '\n  '
            }
          } else {
            let j = i + 1
            if (j < len) {
              if (children[j].classList.contains('Comment')) {
                children[j].innerHTML = '\n    ' + children[j].innerHTML + '\n  '
              }
            }
          }
        }
  
        elem.innerHTML = elem.innerHTML + '\n  '
      }
    }
  }
}

class DocManager {
  constructor(rootDir) {
    this.rootDir = rootDir
  }

  run() {
    for (let file of this.files()) {
      console.log('Polishing:', file)
      const content = Fs.readFileSync(file, 'utf8')
      const dom = new JsDom.JSDOM(content)
      const polisher = new DocPolisher(dom.window.document)
      polisher.polishCSS()
      polisher.polishJS()
      polisher.polishEnums()
      Fs.writeFileSync(file, dom.serialize(), 'utf8')
    }
    Fs.copyFileSync(DOCK_HACK_JS, Path.join(this.rootDir, 'dochack.js'))
  }

  * files() {
    const stat = Fs.statSync(this.rootDir)
    if (stat.isDirectory()) {
    } else if (stat.isFile && (Path.extname(this.rootDir) === '.html' || Path.extname(this.rootDir) === '.htm')) {
      yield this.rootDir
      return
    } else {
      return
    }
    const dirs = [this.rootDir]
    for (let dir of dirs) {
      const names = Fs.readdirSync(dir)
      for (let name of names) {
        const filename = Path.join(dir, name)
        const stat = Fs.statSync(filename)
        if (stat.isDirectory()) {
          dirs.push(filename)
        } else if (stat.isFile && (Path.extname(filename) === '.html' || Path.extname(filename) === '.htm')) {
          yield filename
        }
      }
    }
  }
}

if (typeof process.env.DOC_PLUS_ROOT === 'string') {
  new DocManager(process.env.DOC_PLUS_ROOT).run()
} 
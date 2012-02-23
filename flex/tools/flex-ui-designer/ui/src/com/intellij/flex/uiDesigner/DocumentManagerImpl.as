package com.intellij.flex.uiDesigner {
import cocoa.DocumentWindow;

import com.intellij.flex.uiDesigner.css.CssReader;
import com.intellij.flex.uiDesigner.css.LocalStyleHolder;
import com.intellij.flex.uiDesigner.css.StyleManagerEx;
import com.intellij.flex.uiDesigner.css.StyleValueResolverImpl;
import com.intellij.flex.uiDesigner.flex.MainFocusManagerSB;
import com.intellij.flex.uiDesigner.libraries.FlexLibrarySet;
import com.intellij.flex.uiDesigner.libraries.Library;
import com.intellij.flex.uiDesigner.libraries.LibraryManager;
import com.intellij.flex.uiDesigner.libraries.LibrarySet;
import com.intellij.flex.uiDesigner.libraries.QueueLoader;
import com.intellij.flex.uiDesigner.mxml.FlexMxmlReader;
import com.intellij.flex.uiDesigner.mxml.MxmlReader;
import com.intellij.flex.uiDesigner.ui.DocumentContainer;
import com.intellij.flex.uiDesigner.ui.ProjectView;

import flash.desktop.DockIcon;
import flash.desktop.NativeApplication;
import flash.desktop.NotificationType;
import flash.display.DisplayObject;
import flash.display.NativeWindow;
import flash.display.Stage;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.utils.Dictionary;

import org.jetbrains.ApplicationManager;
import org.osflash.signals.ISignal;
import org.osflash.signals.Signal;

public class DocumentManagerImpl extends EventDispatcher implements DocumentManager {
  private var libraryManager:LibraryManager;

  private var server:Server;

  public function DocumentManagerImpl(libraryManager:LibraryManager, server:Server) {
    this.libraryManager = libraryManager;
    this.server = server;
  }

  private var _documentRendered:ISignal;
  public function get documentRendered():ISignal {
    if (_documentRendered == null) {
      _documentRendered = new Signal();
    }
    return _documentRendered;
  }

  private var _documentUpdated:ISignal;
  public function get documentUpdated():ISignal {
    if (_documentUpdated == null) {
      _documentUpdated = new Signal();
    }
    return _documentUpdated;
  }

  private var _documentChanged:ISignal;
  public function get documentChanged():ISignal {
    if (_documentChanged == null) {
      _documentChanged = new Signal();
    }
    return _documentChanged;
  }

  private var _document:Document;
  [Bindable(event="documentChanged")]
  public function get document():Document {
    return _document;
  }

  public function set document(value:Document):void {
    if (value != document) {
      _document = value;
      dispatchEvent(new Event("documentChanged"));
      if (_documentChanged != null) {
        _documentChanged.dispatch();
      }
      if (_document != null) {
        adjustElementSelection();
      }
    }
  }

  // IDEA-71781, IDEA-71779
  private function adjustElementSelection():void {
    ComponentManager(_document.module.project.getComponent(ComponentManager)).component = null;
  }

  private function checkPool(classPool:ClassPool, documentFactory:DocumentFactory, activateAndFocus:Boolean):Boolean {
    if (classPool.filling) {
      classPool.filled.addOnce(function ():void {
        open(documentFactory, activateAndFocus);
      });
      return false;
    }

    return true;
  }

  public function open(documentFactory:DocumentFactory, activateAndFocus:Boolean):void {
    var context:ModuleContextEx = documentFactory.module.context;
    if (!documentFactory.isPureFlash) {
      if (!checkPool(context.getClassPool(FlexLibrarySet.IMAGE_POOL), documentFactory, activateAndFocus)) {
        return;
      }
      if (!checkPool(context.getClassPool(FlexLibrarySet.SWF_POOL), documentFactory, activateAndFocus)) {
        return;
      }
      if (!checkPool(context.getClassPool(FlexLibrarySet.VIEW_POOL), documentFactory, activateAndFocus)) {
        return;
      }
    }

    if (documentFactory.document == null) {
      if (context.librariesResolved) {
        createAndOpen(documentFactory, activateAndFocus);
      }
      else {
        libraryManager.resolve(documentFactory.module.librarySets, doOpenAfterResolveLibraries, documentFactory, activateAndFocus);
      }
    }
    else if (doOpen(documentFactory, documentFactory.document, activateAndFocus)) {
      if (documentFactory.document == document) {
        adjustElementSelection();
        if (_documentUpdated != null) {
          _documentUpdated.dispatch();
        }
      }

      DocumentContainer(document.container).documentUpdated();
    }
  }

  private function doOpenAfterResolveLibraries(documentFactory:DocumentFactory, activateAndFocus:Boolean):void {
    var module:Module = documentFactory.module;
    if (createAndOpen(documentFactory, activateAndFocus) && !ApplicationManager.instance.unitTestMode) {
      if (NativeWindow.supportsNotification) {
        module.project.window.notifyUser(NotificationType.INFORMATIONAL);
      }
      else {
        var dockIcon:DockIcon = NativeApplication.nativeApplication.icon as DockIcon;
        if (dockIcon != null) {
          dockIcon.bounce(NotificationType.INFORMATIONAL);
        }
      }
    }
  }

  private function createAndOpen(documentFactory:DocumentFactory, activateAndFocus:Boolean):Boolean {
    var document:Document = new Document(documentFactory);
    var module:Module = documentFactory.module;
    if (!documentFactory.isPureFlash) {
      createStyleManager(document, module);
    }

    createDocumentDisplayManager(document, module, documentFactory.isPureFlash);

    if (doOpen(documentFactory, document, activateAndFocus)) {
      documentFactory.document = document;
      var w:DocumentWindow = module.project.window;
      var projectView:ProjectView = ProjectView(w.contentView);
      projectView.addDocument(document);
      this.document = document;
      projectView.selectEditorTab(document);
      return true;
    }
    else {
      return false;
    }
  }

  private function doOpen(documentFactory:DocumentFactory, document:Document, activateAndFocus:Boolean):Boolean {
    var documentReader:DocumentReader = documentFactory.isPureFlash ? new MxmlReader() : new FlexMxmlReader(document.displayManager);
    try {
      server.moduleForGetResourceBundle = documentFactory.module;
      // IDEA-72499
      document.displayManager.setStyleManagerForTalentAdobeEngineers(true);
      var object:DisplayObject = DisplayObject(documentReader.read(documentFactory.data, documentFactory, document.styleManager));
      document.uiComponent = object;
      document.displayManager.setDocument(object);
    }
    catch (e:Error) {
      UncaughtErrorManager.instance.readDocumentErrorHandler(e, documentFactory);
      return false;
    }
    finally {
      server.moduleForGetResourceBundle = null;
      document.displayManager.setStyleManagerForTalentAdobeEngineers(false);
    }

    if (_documentRendered != null) {
      _documentRendered.dispatch(document);
    }

    Server.instance.documentRendered(document);

    if (activateAndFocus && !ApplicationManager.instance.unitTestMode) {
      NativeApplication.nativeApplication.activate(document.module.project.window);
    }

    return true;
  }

  private static function createStyleManager(document:Document, module:Module):void {
    if (module.context.styleManager == null) {
      createStyleManagerForContext(module.context);
    }

    if (module.localStyleHolders == null) {
      return;
    }

    if (module.isApp && document.documentFactory.isApp) {
      createStyleManagerForAppDocument(document, module);
    }
    else if (!module.hasOwnStyleManager) {
      createStyleManagerForModule(module);
    }
  }

  private static function createCssReader(context:ModuleContextEx, styleManager:StyleManagerEx):CssReader {
    var c:Class = context.getClass("com.intellij.flex.uiDesigner.css.CssReaderImpl");
    var cssReader:CssReader = new c();
    cssReader.styleManager = styleManager;
    return cssReader;
  }

  private static function createChildStyleManager(context:ModuleContextEx):StyleManagerEx {
    return new (context.getClass("com.intellij.flex.uiDesigner.css.ChildStyleManager"))(context.styleManager);
  }
  
  private static function createStyleManagerForContext(context:ModuleContextEx):void {
    var inheritingStyleMapList:Vector.<Dictionary> = new Vector.<Dictionary>();
    var styleManagerClass:Class = context.getClass("com.intellij.flex.uiDesigner.css.RootStyleManager");
    context.styleManager = new styleManagerClass(inheritingStyleMapList, new StyleValueResolverImpl(context));
    var cssReader:CssReader = createCssReader(context, context.styleManager);
    // FakeObjectProxy/FakeBooleanSetProxy/MergedCssStyleDeclaration find in list from 0 to end, then we add in list in reverse order
    // (because the library with index 4 overrides the library with index 2)
    var librarySets:Vector.<LibrarySet> = context.librarySets;
    for (var i:int = librarySets.length - 1; i > -1; i--) {
      var librarySet:LibrarySet = librarySets[i];
      do {
        var libraries:Vector.<Library> = librarySet.items;
        for (var j:int = libraries.length - 1; j > -1; j--) {
          var library:Library = libraries[j];
          if (library.inheritingStyles != null) {
            inheritingStyleMapList.push(library.inheritingStyles);
          }

          if (library.defaultsStyle != null) {
            var virtualFile:VirtualFileImpl = VirtualFileImpl(library.file.createChild("defaults.css"));
            virtualFile.stylesheet = library.defaultsStyle;
            cssReader.read(library.defaultsStyle.rulesets, virtualFile);
          }
        }
      }
      while ((librarySet = librarySet.parent) != null);
    }

    cssReader.finalizeRead();
    inheritingStyleMapList.fixed = true;
  }

  private static function createStyleManagerForModule(module:Module):void {
    var styleManager:StyleManagerEx = createChildStyleManager(module.context);
    module.styleManager = styleManager;
    var cssReader:CssReader = createCssReader(module.context, styleManager);

    var localStyleHolder:LocalStyleHolder = module.localStyleHolders[0];
    cssReader.read(localStyleHolder.getStylesheet(module.project).rulesets, localStyleHolder.file);
    cssReader.finalizeRead();
  }

  private static function createStyleManagerForAppDocument(document:Document, module:Module):void {
    var styleManager:StyleManagerEx = createChildStyleManager(module.context);
    document.styleManager = styleManager;
    var cssReader:CssReader = createCssReader(module.context, styleManager);

    var localStyleHolder:LocalStyleHolder;
    for each (localStyleHolder in module.localStyleHolders) {
      if (localStyleHolder.isApplicable(document.documentFactory)) {
        cssReader.read(localStyleHolder.getStylesheet(module.project).rulesets, localStyleHolder.file);
      }
    }

    cssReader.finalizeRead();
  }

  private function createDocumentDisplayManager(document:Document, module:Module, isPureFlash:Boolean):void {
    var flexModuleFactoryClass:Class = isPureFlash ? null :  module.getClass("com.intellij.flex.uiDesigner.flex.FlexModuleFactory");
    var systemManagerClass:Class = isPureFlash ? FlashDocumentDisplayManager : module.getClass("com.intellij.flex.uiDesigner.flex.FlexDocumentDisplayManager");
    var systemManager:DocumentDisplayManager = new systemManagerClass();
    document.displayManager = systemManager;

    if (!systemManager.sharedInitialized) {
      const stageForAdobeDummies:Stage = QueueLoader.stageForAdobeDummies;
      assert(stageForAdobeDummies != null, "Stage for Adobe dummies cannot be null");
      systemManager.initShared(stageForAdobeDummies, server, UncaughtErrorManager.instance);
    }
    systemManager.init(module.project.window.stage, isPureFlash ? null : new flexModuleFactoryClass(document.styleManager, module.context.applicationDomain), UncaughtErrorManager.instance,
                       MainFocusManagerSB(module.project.window.focusManager), document.documentFactory);
    document.container = new DocumentContainer(systemManager);
  }
}
}
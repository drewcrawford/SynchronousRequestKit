//
//  NSURLSession+Synchronous.swift
//  SynchronousRequestKit
//  Created by Drew Crawford on 8/8/14
//  This file is part of SynchronousRequestKit.  It is subject to the license terms in the LICENSE
//  file found in the top level of this distribution
//  No part of SynchronousRequestKit, including this file, may be copied, modified,
//  propagated, or distributed except according to the terms contained
//  in the LICENSE file.

import Foundation

private var cassettes : [SynchronousDataTask] = []

/**Add a cassette to be played back on the next request. This is primarily used for testing purposes.*/
public func addCassette(string string: String) {
    let response = NSHTTPURLResponse(URL: NSURL(), statusCode: 200, HTTPVersion: nil, headerFields: nil)
    let cassette = SynchronousDataTask(task: NSURLSessionDataTask(), error: nil, data: string.dataUsingEncoding(NSUTF8StringEncoding), response:response)
    cassettes.append(cassette)
}

public func addCassette(path path: String, testClass: AnyClass) {
    let path = NSBundle(forClass: testClass).pathForResource(path, ofType: "cassette")
    let data = NSData(contentsOfFile: path!)!
    let str = NSString(data: data, encoding: NSUTF8StringEncoding)
    addCassette(string: str as! String)
}


enum SynchronousDataTaskError : ErrorType {
    case NoData
    case BadHTTPStatus(code: Int, body: String?)
    case NotHTTPResponse
    case NoResponse
    case NotUTF8
    case NotJSONDict
}

import Foundation
private let errorDomain = "SynchronousDataTaskErrorDomain"
public final class SynchronousDataTask {
    public var task: NSURLSessionDataTask
    
    /**The error, if any, returned by Cocoa.  If you want a better error, try errorOrData/errorOrString. */
    public var underlyingCocoaError: NSError?
    public var underlyingCocoaData: NSData?
    public var underlyingCocoaResponse: NSURLResponse?
    
    private init(task: NSURLSessionDataTask, error: NSError?, data: NSData?, response:NSURLResponse?) {
        self.underlyingCocoaData = data
        self.underlyingCocoaError = error
        self.underlyingCocoaResponse = response
        self.task = task
    }
    
    /**Performs some basic error checking on the result.
    
    This function tries to get some data for the request.
    
    */
    public func getData() throws -> NSData {
        if let cocoaError = underlyingCocoaError { //may have an error already
            throw cocoaError
        }
        if underlyingCocoaResponse == nil {
            throw SynchronousDataTaskError.NoResponse
        }
        guard let myResponse = underlyingCocoaResponse as? NSHTTPURLResponse else {
            throw SynchronousDataTaskError.NotHTTPResponse
            
        }
        if myResponse.statusCode < 200 || myResponse.statusCode >= 300 {
            throw SynchronousDataTaskError.BadHTTPStatus(code: myResponse.statusCode, body: _string)
        }
        guard let d = underlyingCocoaData else {
            throw SynchronousDataTaskError.NoData
        }
        return d
    }
    
    /**Gets the string, if available.  Performs as little error checking as possible.
    - note: If *any* string can be returned for the request, this function will do it.  This is useful if you want to return a string as part of an error message.*/
    var _string : String? {
        get {
            guard let data = underlyingCocoaData else { return nil }
            guard let str = NSString(data: data, encoding: NSUTF8StringEncoding) else { return nil }
            return str as String
        }
    }
    
    /**Performs some error checking on the result.
    
    This function tries to get a UTF-8 string for the request.
    */
    public func getString() throws -> String {
        let data = try self.getData()
        guard let str = NSString(data: data, encoding: NSUTF8StringEncoding) else { throw SynchronousDataTaskError.NotUTF8 }
        return str as String
    }
    
    /**This function tries to get a JSON dictionary for the request. */
    public func getJsonDict() throws -> [String: AnyObject] {
        let data = try getData()
        let jsonObj = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())
        if let j = jsonObj as? [String: AnyObject] {
            return j
        }
        throw SynchronousDataTaskError.NotJSONDict
    }
    
    /**This checks the response to see if it's a well-known string. */
    public func isParticularError(code code: Int, body: String) -> Bool {
        guard let myResponse = underlyingCocoaResponse as? NSHTTPURLResponse else { return false }
        if myResponse.statusCode != code {
            return false
        }
        guard let u = underlyingCocoaData else {
            return false
        }
        let str = NSString(data: u, encoding: NSUTF8StringEncoding)
        guard let s = str else { return false }
        if s != body {
            return false
        }
        return true
    }
}
extension NSURLSession {
    
    public func synchronousDataRequestWithRequest(request: NSURLRequest) -> SynchronousDataTask {
        if cassettes.count > 0 {
            return cassettes.removeFirst()
        }
        
        let sema = dispatch_semaphore_create(0)
        var data : NSData?
        var response : NSURLResponse?
        var error : NSError?
        let task = self.dataTaskWithRequest(request) { (ldata, lresponse, lerror) -> Void in
            data = ldata
            response = lresponse
            error = lerror
            dispatch_semaphore_signal(sema);
            return;
        }
        task.resume()
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER)
        return SynchronousDataTask(task: task, error: error, data: data, response: response)
    }
}

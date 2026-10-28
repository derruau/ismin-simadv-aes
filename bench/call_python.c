#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <Python.h>
#include <dlfcn.h>

// Path to the TP folder, where aes_tb.sv lives.
#define TP_PATH "\"./TP\""

// Selects the operation for the AES, either encryption or decryption
typedef enum {
    ENCDEC_DEC = 0, // Decryption
    ENCDEC_ENC = 1  // Encryption
} encdec_t;

// Test function
int test(int a){
    return a*2;
}

// Initializes Python.
// Must be called before aes_c
// SV import signature:
// import "DPI-C" function int python_initialize_c();
int python_initialize_c(){
    // PYTHON_SHARED_LIB Must be defined either as a compilation macro or before
    #ifdef PYTHON_SHARED_LIB
    void *dl_pt;

    dl_pt = dlopen(PYTHON_SHARED_LIB, RTLD_NOW | RTLD_GLOBAL);

    if (dl_pt == NULL) {
        fprintf(stderr, "Error, can't find Python Shared Library. Maybe check the PYTHON_SHARED_LIB path!");
        exit(1);
    }

    // Initialize Python
    Py_Initialize();
    PyRun_SimpleString("import sys");
    // Append path to python scripts
    PyRun_SimpleString("sys.path.append(" TP_PATH ")");

    return 0;

    #else
    fprintf(
        stderr,
        "Error, please define the path of the PYTHON_SHARED_LIB during "
        "compilation. (Use GCC option -DPYTHON_SHARED_LIB=[PATH]) \n"
    );

    return 1;
    #endif
}

// Ends the python process.
// Must be called at the end of the program.
// SV Import signature:
// import "DPI-C" function void python_finalize_c();
void python_finalize_c(){
    Py_Finalize();
}

// AES Encryption (ECB Mode) of a block from a key.
// `dataIn` - should be 128 bytes long.
// `keyIn` - should either be 128 or 256 bytes long.
// `encdec` - either ENCDEC_ENC for encryption or ENCDEC_DEC for decryption
// SV Import signature:
// import "DPI-C" function string aes_c(input string dataIn, input string keyIn, input int encdec);
const char* aes_c(const char* dataIn, const char* keyIn, encdec_t encdec)
{
    PyObject *pModule = NULL;
    PyObject *pFunc   = NULL;
    PyObject *pArgs   = NULL;
    PyObject *pValue  = NULL;
    PyObject *pyData  = NULL;
    PyObject *pyKey   = NULL;
    PyObject *pyOp   = NULL;

    // Static because the returned pointer must remain valid
    // after this C function returns.
    static char py_out[128];

    py_out[0] = '\0';

    //----------------------------------------------------------
    // Import Python module
    //----------------------------------------------------------
    pModule = PyImport_ImportModule("aes_live_test");

    if (pModule == NULL) {
        PyErr_Print();
        fprintf(stderr, "Error while importing aes_live_test\n");
        return "";
    }

    //----------------------------------------------------------
    // Get Python function
    //----------------------------------------------------------
    pFunc = PyObject_GetAttrString(pModule, "AES_ref_py");

    if (pFunc == NULL || !PyCallable_Check(pFunc)) {
        PyErr_Print();
        fprintf(stderr, "Cannot find callable function AES_ref_py\n");

        Py_XDECREF(pFunc);
        Py_DECREF(pModule);
        return "";
    }

    //----------------------------------------------------------
    // Convert C strings into Python strings
    //----------------------------------------------------------
    pyData = PyUnicode_FromString(dataIn);
    pyKey  = PyUnicode_FromString(keyIn);
    pyOp   = PyLong_FromLong(encdec);

    if (pyData == NULL || pyKey == NULL || pyOp == NULL) {
        PyErr_Print();
        fprintf(stderr, "Could not convert arguments to Python strings\n");

        Py_XDECREF(pyData);
        Py_XDECREF(pyKey);
        Py_XDECREF(pyOp);
        Py_DECREF(pFunc);
        Py_DECREF(pModule);
        return "";
    }

    //----------------------------------------------------------
    // Build Python argument tuple
    //----------------------------------------------------------
    pArgs = PyTuple_Pack(3, pyData, pyKey, pyOp);


    // PyTuple_Pack keeps references to them,
    // so our own references can now be released.
    Py_DECREF(pyData);
    Py_DECREF(pyKey);
    Py_DECREF(pyOp);

    if (pArgs == NULL) {
        PyErr_Print();
        fprintf(stderr, "Could not create Python argument tuple\n");

        Py_DECREF(pFunc);
        Py_DECREF(pModule);
        return "";
    }

    //----------------------------------------------------------
    // Call AES_ref_py(dataIn, keyIn)
    //----------------------------------------------------------
    pValue = PyObject_CallObject(pFunc, pArgs);

    if (pValue == NULL) {
        PyErr_Print();
        fprintf(stderr, "Call to AES_ref_py failed\n");

        Py_DECREF(pArgs);
        Py_DECREF(pFunc);
        Py_DECREF(pModule);
        return "";
    }

    //----------------------------------------------------------
    // Make sure Python returned a string
    //----------------------------------------------------------
    if (!PyUnicode_Check(pValue)) {
        fprintf(stderr, "AES_ref_py did not return a Python string\n");

        Py_DECREF(pValue);
        Py_DECREF(pArgs);
        Py_DECREF(pFunc);
        Py_DECREF(pModule);
        return "";
    }

    //----------------------------------------------------------
    // Python string -> C string
    //----------------------------------------------------------
    const char *tmp = PyUnicode_AsUTF8(pValue);

    if (tmp == NULL) {
        PyErr_Print();
        fprintf(stderr, "Could not convert Python result to C string\n");

        Py_DECREF(pValue);
        Py_DECREF(pArgs);
        Py_DECREF(pFunc);
        Py_DECREF(pModule);
        return "";
    }

    /*
     * IMPORTANT:
     * tmp belongs to pValue, so copy it BEFORE Py_DECREF(pValue).
     */
    snprintf(py_out, sizeof(py_out), "%s", tmp);

    //----------------------------------------------------------
    // Cleanup
    //----------------------------------------------------------
    Py_DECREF(pValue);
    Py_DECREF(pArgs);
    Py_DECREF(pFunc);
    Py_DECREF(pModule);

    return py_out;
}

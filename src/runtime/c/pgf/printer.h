#ifndef PRINTER_H
#define PRINTER_H

class PGF_INTERNAL_DECL PgfPrinter : public PgfUnmarshaller {
    // List of free variables in order reverse to the order of binding
    PgfPrintContext *ctxt;

    // Each lambda abstraction is a separate object, but when we print
    // them we want to colapse them into one abstraction with
    // several variables. For that reason, if we are in the process
    // of printing nested lambda abstractions, printing_lambdas is true
    // and btype is the binding type for the last variable.
    bool printing_lambdas;
    PgfBindType btype;

    // This method should be called before printing any other form of
    // expression but a lambda. In this way the printing of a chain
    // of lambda expressions is finished.
    void flush_lambdas();

    // Push a new variable in the printing context. If the name
    // collides with an existing variable, the variable is renamed
    // by adding a number.
    void push_variable(PgfText *name);

    // Pop the last variable name from the context.
    void pop_variable();

    // The current operator priority
    int prio;

    // The generated text
    PgfText *res;

    // The marshaller for pattern matching
    PgfMarshaller *m;

public:
    PgfPrinter(PgfPrintContext *context, int priority,
               PgfMarshaller *marshaller);

    void puts(PgfText *s);
    void puts(const char *s);
    void nprintf(size_t buf_size, const char *format, ...) __attribute__ ((format (printf, 3, 4)));

    PgfText *get_text();

    virtual uintptr_t eabs(PgfBindType btype, PgfText *name, uintptr_t body);
    virtual uintptr_t eapp(uintptr_t fun, uintptr_t arg);
    virtual uintptr_t elit(uintptr_t lit);
    virtual uintptr_t emeta(PgfMetaId meta);
    virtual uintptr_t efun(PgfText *name);
    virtual uintptr_t evar(int index);
    virtual uintptr_t etyped(uintptr_t expr, uintptr_t typ);
    virtual uintptr_t eimplarg(uintptr_t expr);
    virtual uintptr_t lint(int v);
    virtual uintptr_t lflt(double v);
    virtual uintptr_t lstr(PgfText *v);
    virtual uintptr_t dtyp(int n_hypos, PgfTypeHypo *hypos,
                           PgfText *cat,
                           int n_exprs, uintptr_t *exprs);
    virtual void free_ref(uintptr_t x);
};

#endif
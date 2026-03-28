#if defined _great_sage_included
  #endinput
#endif
#define _great_sage_included

/**
 * Se apeleaza cand un jucator devine Great Sage.
 */
forward user_become_sage(id);

/**
 * Verifica daca un jucator este Great Sage.
 */
native is_user_sage(id);

/**
 * Seteaza sau scoate statusul de Great Sage pentru un jucator.
 */
native set_user_sage(id, bool:status);
